defmodule Jido.Signal.Bus.PersistentSubscription do
  @moduledoc """
  A GenServer that manages persistent subscription state and checkpoints for a single subscriber.

  This module maintains the subscription state for a client, tracking which signals have been
  acknowledged and allowing clients to resume from their last checkpoint after disconnection.
  Each instance maps 1:1 to a bus subscriber and is managed as a child of the Bus's dynamic supervisor.
  """
  use GenServer

  alias Jido.Signal.Dispatch
  alias Jido.Signal.ID
  alias Jido.Signal.Telemetry

  require Logger

  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Zoi.string(),
              bus_pid: Zoi.any(),
              bus_subscription: Zoi.any() |> Zoi.nullable() |> Zoi.optional(),
              client_pid: Zoi.any(),
              checkpoint: Zoi.default(Zoi.integer(), 0) |> Zoi.optional(),
              max_in_flight: Zoi.default(Zoi.integer(), 1000) |> Zoi.optional(),
              max_pending: Zoi.default(Zoi.integer(), 10_000) |> Zoi.optional(),
              in_flight_signals: Zoi.default(Zoi.map(), %{}) |> Zoi.optional(),
              pending_signals: Zoi.default(Zoi.map(), %{}) |> Zoi.optional(),
              max_attempts: Zoi.default(Zoi.integer(), 5) |> Zoi.optional(),
              attempts: Zoi.default(Zoi.map(), %{}) |> Zoi.optional(),
              retry_interval: Zoi.default(Zoi.integer(), 100) |> Zoi.optional(),
              retry_timer_ref: Zoi.any() |> Zoi.nullable() |> Zoi.optional(),
              client_monitor_ref: Zoi.any() |> Zoi.nullable() |> Zoi.optional(),
              task_supervisor: Zoi.any() |> Zoi.nullable() |> Zoi.optional(),
              journal_adapter: Zoi.atom() |> Zoi.nullable() |> Zoi.optional(),
              journal_pid: Zoi.any() |> Zoi.nullable() |> Zoi.optional(),
              checkpoint_key: Zoi.string() |> Zoi.nullable() |> Zoi.optional()
            }
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for PersistentSubscription"
  def schema, do: @schema

  # Client API

  @doc """
  Starts a new persistent subscription process.

  Options:
  - id: Unique identifier for this subscription (required)
  - bus_pid: PID of the bus this subscription belongs to (required)
  - path: Signal path pattern to subscribe to (required)
  - start_from: Where to start reading signals from (:origin, :current, or timestamp)
  - max_in_flight: Maximum number of unacknowledged signals (default: 1000)
  - max_pending: Maximum number of pending signals before backpressure (default: 10_000)
  - client_pid: PID of the client process (required)
  - dispatch_opts: Additional dispatch options for the subscription
  """
  def start_link(opts) do
    id = Keyword.get(opts, :id) || ID.generate!()
    opts = Keyword.put(opts, :id, id)

    # Validate start_from value and set default if invalid
    opts =
      case Keyword.get(opts, :start_from, :origin) do
        :origin ->
          opts

        :current ->
          opts

        timestamp when is_integer(timestamp) and timestamp >= 0 ->
          opts

        _invalid ->
          Keyword.put(opts, :start_from, :origin)
      end

    GenServer.start_link(__MODULE__, opts, name: via_tuple(id))
  end

  defdelegate via_tuple(id), to: Jido.Signal.Util
  defdelegate whereis(id), to: Jido.Signal.Util

  @impl GenServer
  def init(opts) do
    Process.flag(:trap_exit, true)

    # Extract the bus subscription
    bus_subscription = Keyword.fetch!(opts, :bus_subscription)

    id = Keyword.fetch!(opts, :id)
    journal_adapter = Keyword.get(opts, :journal_adapter)
    journal_pid = Keyword.get(opts, :journal_pid)
    bus_name = Keyword.get(opts, :bus_name, :unknown)

    # Compute checkpoint key (unique per bus + subscription)
    checkpoint_key = "#{bus_name}:#{id}"

    # Load checkpoint from journal if adapter is configured
    loaded_checkpoint =
      if journal_adapter do
        case journal_adapter.get_checkpoint(checkpoint_key, journal_pid) do
          {:ok, cp} ->
            cp

          {:error, :not_found} ->
            0

          {:error, reason} ->
            Logger.warning("Failed to load checkpoint for #{checkpoint_key}: #{inspect(reason)}")

            0
        end
      else
        Keyword.get(opts, :checkpoint, 0)
      end

    state = %__MODULE__{
      id: id,
      bus_pid: Keyword.fetch!(opts, :bus_pid),
      bus_subscription: bus_subscription,
      client_pid: Keyword.get(opts, :client_pid),
      checkpoint: loaded_checkpoint,
      max_in_flight: Keyword.get(opts, :max_in_flight, 1000),
      max_pending: Keyword.get(opts, :max_pending, 10_000),
      max_attempts: Keyword.get(opts, :max_attempts, 5),
      retry_interval: Keyword.get(opts, :retry_interval, 100),
      task_supervisor: Keyword.get(opts, :task_supervisor, Jido.Signal.TaskSupervisor),
      in_flight_signals: %{},
      pending_signals: %{},
      attempts: %{},
      journal_adapter: journal_adapter,
      journal_pid: journal_pid,
      checkpoint_key: checkpoint_key
    }

    # Establish monitor without alive?/monitor race.
    state = maybe_monitor_client(state, state.client_pid)

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:ack, signal_log_id}, _from, state) when is_binary(signal_log_id) do
    case acknowledge_signal_log_ids(state, [signal_log_id]) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:ack, signal_log_ids}, _from, state) when is_list(signal_log_ids) do
    case acknowledge_signal_log_ids(state, signal_log_ids) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:ack, _invalid_arg}, _from, state) do
    {:reply, {:error, :invalid_ack_argument}, state}
  end

  @impl GenServer
  def handle_call({:signal, {signal_log_id, signal}}, _from, state) do
    case enqueue_signal(state, signal_log_id, signal) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}

      {:error, :queue_full, new_state} ->
        {:reply, {:error, :queue_full}, new_state}
    end
  end

  @impl GenServer
  def handle_call({:signal_batch, signal_entries}, _from, state) when is_list(signal_entries) do
    case enqueue_signal_batch(state, signal_entries) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}

      {:error, :queue_full, new_state} ->
        {:reply, {:error, :queue_full}, new_state}
    end
  end

  @impl GenServer
  def handle_call(_req, _from, state) do
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_cast({:ack, signal_log_id}, state) when is_binary(signal_log_id) do
    case acknowledge_signal_log_ids(state, [signal_log_id]) do
      {:ok, new_state} -> {:noreply, new_state}
      {:error, _reason} -> {:noreply, state}
    end
  end

  @impl GenServer
  def handle_cast({:ack, _invalid_arg}, state), do: {:noreply, state}

  @impl GenServer
  def handle_cast({:reconnect, new_client_pid}, state) do
    # Update the bus subscription to point to the new client PID.
    updated_subscription = %{
      state.bus_subscription
      | dispatch: {:pid, target: new_client_pid, delivery_mode: :async}
    }

    # Replace stale monitor ref before monitoring new client.
    new_state =
      state
      |> Map.put(:client_pid, new_client_pid)
      |> Map.put(:bus_subscription, updated_subscription)
      |> maybe_monitor_client(new_client_pid)

    # Replay any signals that were missed while disconnected.
    new_state = replay_missed_signals(new_state)

    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info({:signal, {signal_log_id, signal}}, state) do
    case enqueue_signal(state, signal_log_id, signal) do
      {:ok, new_state} ->
        {:noreply, new_state}

      {:error, :queue_full, new_state} ->
        Logger.warning("Dropping signal #{signal_log_id} - subscription #{state.id} queue full")
        {:noreply, new_state}
    end
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, pid, _reason}, %{client_pid: client_pid} = state)
      when pid == client_pid do
    # Client disconnected, but we keep the subscription alive
    # The client can reconnect later using the reconnect/2 function
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(:retry_pending, state) do
    # Clear the timer ref since we're handling it now
    state = %{state | retry_timer_ref: nil}

    # Process pending signals that need retry
    new_state = process_pending_for_retry(state)

    {:noreply, new_state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Helper function to replay missed signals
  defp replay_missed_signals(state) do
    Logger.debug("Replaying missed signals for subscription #{state.id}")

    missed_signals = fetch_signals_since_checkpoint(state)

    Enum.each(missed_signals, fn {signal_log_id, signal} ->
      replay_single_signal(signal_log_id, signal, state)
    end)

    state
  end

  @spec enqueue_signal_batch(t(), list({String.t(), term()})) ::
          {:ok, t()} | {:error, :queue_full, t()}
  defp enqueue_signal_batch(state, signal_entries) do
    Enum.reduce_while(signal_entries, {:ok, state}, fn {signal_log_id, signal},
                                                       {:ok, acc_state} ->
      case enqueue_signal(acc_state, signal_log_id, signal) do
        {:ok, next_state} ->
          {:cont, {:ok, next_state}}

        {:error, :queue_full, next_state} ->
          {:halt, {:error, :queue_full, next_state}}
      end
    end)
  end

  @spec enqueue_signal(t(), String.t(), term()) :: {:ok, t()} | {:error, :queue_full, t()}
  defp enqueue_signal(state, signal_log_id, signal) do
    cond do
      map_size(state.in_flight_signals) < state.max_in_flight ->
        {:ok, dispatch_signal(state, signal_log_id, signal)}

      map_size(state.pending_signals) < state.max_pending ->
        new_pending = Map.put(state.pending_signals, signal_log_id, signal)
        {:ok, %{state | pending_signals: new_pending}}

      true ->
        emit_backpressure_telemetry(state)
        {:error, :queue_full, state}
    end
  end

  defp emit_backpressure_telemetry(state) do
    Telemetry.execute(
      [:jido, :signal, :subscription, :backpressure],
      %{},
      %{
        subscription_id: state.id,
        in_flight: map_size(state.in_flight_signals),
        pending: map_size(state.pending_signals)
      }
    )
  end

  defp fetch_signals_since_checkpoint(state) do
    try do
      case GenServer.call(state.bus_pid, {:signals_since, state.checkpoint}) do
        {:ok, signals} when is_list(signals) -> signals
        _ -> []
      end
    catch
      :exit, _reason -> []
    end
  end

  defp signal_after_checkpoint?(signal_log_id, signal, checkpoint) do
    signal_timestamp_ms(signal_log_id, signal) > checkpoint
  end

  defp replay_single_signal(signal_log_id, signal, state) do
    if signal_after_checkpoint?(signal_log_id, signal, state.checkpoint) do
      dispatch_replay_signal(signal, state)
    end
  end

  defp signal_timestamp_ms(signal_log_id, signal) do
    case safe_extract_timestamp(signal_log_id) do
      {:ok, ts} ->
        ts

      :error ->
        case DateTime.from_iso8601(signal.time) do
          {:ok, timestamp, _offset} -> DateTime.to_unix(timestamp, :millisecond)
          _ -> 0
        end
    end
  end

  defp safe_extract_timestamp(signal_log_id) when is_binary(signal_log_id) do
    {:ok, ID.extract_timestamp(signal_log_id)}
  rescue
    _ -> :error
  end

  defp safe_extract_timestamp(_), do: :error

  defp dispatch_replay_signal(signal, state) do
    case Dispatch.dispatch(signal, state.bus_subscription.dispatch,
           task_supervisor: state.task_supervisor
         ) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.debug(
          "Dispatch failed during replay, signal: #{inspect(signal)}, reason: #{inspect(reason)}"
        )
    end
  end

  @impl GenServer
  def terminate(_reason, state) do
    maybe_cancel_retry_timer(state.retry_timer_ref)
    maybe_demonitor_client(state.client_monitor_ref)

    :ok
  end

  defp maybe_monitor_client(state, client_pid) when is_pid(client_pid) do
    maybe_demonitor_client(state.client_monitor_ref)
    monitor_ref = Process.monitor(client_pid)
    %{state | client_monitor_ref: monitor_ref}
  end

  defp maybe_monitor_client(state, _client_pid), do: state

  defp maybe_demonitor_client(nil), do: :ok

  defp maybe_demonitor_client(monitor_ref) do
    Process.demonitor(monitor_ref, [:flush])
    :ok
  end

  defp maybe_cancel_retry_timer(nil), do: :ok

  defp maybe_cancel_retry_timer(timer_ref) do
    Process.cancel_timer(timer_ref)
    :ok
  end

  # Private Helpers

  @spec acknowledge_signal_log_ids(t(), list(String.t())) :: {:ok, t()} | {:error, term()}
  defp acknowledge_signal_log_ids(state, signal_log_ids) do
    with :ok <- validate_ack_signal_log_ids(signal_log_ids),
         {:ok, resolved_signal_log_ids} <- resolve_ack_signal_log_ids(state, signal_log_ids),
         {:ok, timestamps} <- collect_ack_timestamps(resolved_signal_log_ids) do
      highest_timestamp = Enum.max(timestamps)
      new_checkpoint = max(state.checkpoint, highest_timestamp)

      persist_checkpoint(state, new_checkpoint)

      new_in_flight =
        Enum.reduce(resolved_signal_log_ids, state.in_flight_signals, fn id, acc ->
          Map.delete(acc, id)
        end)

      new_state = %{state | in_flight_signals: new_in_flight, checkpoint: new_checkpoint}
      {:ok, process_pending_signals(new_state)}
    end
  end

  @spec validate_ack_signal_log_ids(list(term())) :: :ok | {:error, :invalid_ack_argument}
  defp validate_ack_signal_log_ids([]), do: {:error, :invalid_ack_argument}

  defp validate_ack_signal_log_ids(signal_log_ids) when is_list(signal_log_ids) do
    if Enum.all?(signal_log_ids, &is_binary/1) do
      :ok
    else
      {:error, :invalid_ack_argument}
    end
  end

  @spec collect_ack_timestamps(list(String.t())) ::
          {:ok, list(non_neg_integer())} | {:error, term()}
  defp collect_ack_timestamps(signal_log_ids) do
    Enum.reduce_while(signal_log_ids, {:ok, []}, fn signal_log_id, {:ok, acc} ->
      case ack_timestamp(signal_log_id) do
        {:ok, timestamp} -> {:cont, {:ok, [timestamp | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @spec resolve_ack_signal_log_ids(t(), list(String.t())) ::
          {:ok, list(String.t())} | {:error, term()}
  defp resolve_ack_signal_log_ids(state, signal_log_ids) do
    Enum.reduce_while(signal_log_ids, {:ok, []}, fn ack_identifier, {:ok, acc} ->
      case resolve_ack_signal_log_id(state, ack_identifier) do
        {:ok, signal_log_id} -> {:cont, {:ok, [signal_log_id | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @spec resolve_ack_signal_log_id(t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  defp resolve_ack_signal_log_id(state, ack_identifier) do
    cond do
      Map.has_key?(state.in_flight_signals, ack_identifier) ->
        {:ok, ack_identifier}

      true ->
        case Enum.find(state.in_flight_signals, fn {_signal_log_id, signal} ->
               is_map(signal) and Map.get(signal, :id) == ack_identifier
             end) do
          {signal_log_id, _signal} ->
            {:ok, signal_log_id}

          nil ->
            if ID.valid?(ack_identifier) do
              {:error, {:unknown_signal_log_id, ack_identifier}}
            else
              {:error, {:invalid_signal_log_id, ack_identifier}}
            end
        end
    end
  end

  @spec ack_timestamp(String.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  defp ack_timestamp(signal_log_id) do
    {:ok, ID.extract_timestamp(signal_log_id)}
  rescue
    _error -> {:error, {:invalid_signal_log_id, signal_log_id}}
  end

  # Persists checkpoint to journal if adapter is configured
  @spec persist_checkpoint(t(), non_neg_integer()) :: :ok
  defp persist_checkpoint(%{journal_adapter: nil}, _checkpoint), do: :ok

  defp persist_checkpoint(state, checkpoint) do
    case state.journal_adapter.put_checkpoint(state.checkpoint_key, checkpoint, state.journal_pid) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "Failed to persist checkpoint for #{state.checkpoint_key}: #{inspect(reason)}"
        )

        :ok
    end
  end

  # Helper function to process pending signals if we have capacity
  # Only processes signals that haven't failed yet (no attempt count)
  @spec process_pending_signals(t()) :: t()
  defp process_pending_signals(state) do
    # Check if we have pending signals and space in the in-flight queue
    available_capacity = state.max_in_flight - map_size(state.in_flight_signals)

    # Find pending signals that haven't failed yet (no attempt count)
    new_pending_signals =
      Enum.filter(state.pending_signals, fn {id, _signal} ->
        not Map.has_key?(state.attempts, id)
      end)
      |> Map.new()

    if available_capacity > 0 && map_size(new_pending_signals) > 0 do
      # Get the first pending signal (using Enum.at to get the first key-value pair)
      {signal_id, signal} =
        new_pending_signals
        |> Enum.sort_by(fn {id, _} -> id end)
        |> List.first()

      # Remove from pending before dispatching
      new_pending = Map.delete(state.pending_signals, signal_id)
      state = %{state | pending_signals: new_pending}

      # Dispatch the signal using the configured dispatch mechanism
      new_state = dispatch_signal(state, signal_id, signal)

      # Recursively process more pending signals if available
      process_pending_signals(new_state)
    else
      # No change needed
      state
    end
  end

  # Process pending signals that are awaiting retry (have attempt counts)
  @spec process_pending_for_retry(t()) :: t()
  defp process_pending_for_retry(state) do
    # Find all pending signals that have attempt counts (i.e., failed signals)
    retry_signals =
      Enum.filter(state.pending_signals, fn {id, _signal} ->
        Map.has_key?(state.attempts, id)
      end)

    Enum.reduce(retry_signals, state, fn {signal_id, signal}, acc_state ->
      # Only process if we have in-flight capacity
      if map_size(acc_state.in_flight_signals) < acc_state.max_in_flight do
        # Remove from pending before dispatching
        new_pending = Map.delete(acc_state.pending_signals, signal_id)
        acc_state = %{acc_state | pending_signals: new_pending}

        # Dispatch the signal (this will handle success, failure, or DLQ)
        dispatch_signal(acc_state, signal_id, signal)
      else
        # No capacity, stop processing
        acc_state
      end
    end)
  end

  # Dispatches a signal and handles success/failure with retry tracking
  @spec dispatch_signal(t(), String.t(), term()) :: t()
  defp dispatch_signal(state, signal_log_id, signal) do
    if state.bus_subscription.dispatch do
      result =
        Dispatch.dispatch(signal, state.bus_subscription.dispatch,
          task_supervisor: state.task_supervisor
        )

      handle_dispatch_result(result, state, signal_log_id, signal)
    else
      # No dispatch configured - just add to in-flight
      new_in_flight = Map.put(state.in_flight_signals, signal_log_id, signal)
      %{state | in_flight_signals: new_in_flight}
    end
  end

  defp handle_dispatch_result(:ok, state, signal_log_id, signal) do
    # Success - clear attempts for this signal and add to in-flight
    new_attempts = Map.delete(state.attempts, signal_log_id)
    new_in_flight = Map.put(state.in_flight_signals, signal_log_id, signal)
    %{state | in_flight_signals: new_in_flight, attempts: new_attempts}
  end

  defp handle_dispatch_result({:error, reason}, state, signal_log_id, signal) do
    # Failure - increment attempts
    current_attempts = Map.get(state.attempts, signal_log_id, 0) + 1

    if current_attempts >= state.max_attempts do
      # Move to DLQ
      handle_dlq(state, signal_log_id, signal, reason, current_attempts)
    else
      handle_dispatch_retry(state, signal_log_id, signal, current_attempts)
    end
  end

  defp handle_dispatch_retry(state, signal_log_id, signal, current_attempts) do
    # Keep for retry - add to pending for later retry, update attempts
    Telemetry.execute(
      [:jido, :signal, :subscription, :dispatch, :retry],
      %{attempt: current_attempts},
      %{subscription_id: state.id, signal_id: signal.id}
    )

    new_attempts = Map.put(state.attempts, signal_log_id, current_attempts)
    new_pending = Map.put(state.pending_signals, signal_log_id, signal)
    state = %{state | pending_signals: new_pending, attempts: new_attempts}
    schedule_retry(state)
  end

  # Schedules a retry timer if one is not already scheduled
  @spec schedule_retry(t()) :: t()
  defp schedule_retry(%{retry_timer_ref: nil} = state) do
    timer_ref = Process.send_after(self(), :retry_pending, state.retry_interval)
    %{state | retry_timer_ref: timer_ref}
  end

  defp schedule_retry(state) do
    # Timer already scheduled
    state
  end

  # Handles moving a signal to the Dead Letter Queue after max attempts
  @spec handle_dlq(t(), String.t(), term(), term(), non_neg_integer()) :: t()
  defp handle_dlq(state, signal_log_id, signal, reason, attempt_count) do
    metadata = %{
      attempt_count: attempt_count,
      last_error: inspect(reason),
      subscription_id: state.id,
      signal_log_id: signal_log_id
    }

    if state.journal_adapter do
      case state.journal_adapter.put_dlq_entry(
             state.id,
             signal,
             reason,
             metadata,
             state.journal_pid
           ) do
        {:ok, dlq_id} ->
          Telemetry.execute(
            [:jido, :signal, :subscription, :dlq],
            %{},
            %{
              subscription_id: state.id,
              signal_id: signal.id,
              dlq_id: dlq_id,
              attempts: attempt_count
            }
          )

          Logger.debug("Signal #{signal.id} moved to DLQ after #{attempt_count} attempts")

        {:error, dlq_error} ->
          Logger.error("Failed to write to DLQ for signal #{signal.id}: #{inspect(dlq_error)}")
      end
    else
      Logger.warning(
        "Signal #{signal.id} exhausted #{attempt_count} attempts but no DLQ configured"
      )
    end

    # Remove from tracking - signal is now in DLQ (or dropped if no DLQ)
    new_in_flight = Map.delete(state.in_flight_signals, signal_log_id)
    new_pending = Map.delete(state.pending_signals, signal_log_id)
    new_attempts = Map.delete(state.attempts, signal_log_id)

    %{
      state
      | in_flight_signals: new_in_flight,
        pending_signals: new_pending,
        attempts: new_attempts
    }
  end
end
