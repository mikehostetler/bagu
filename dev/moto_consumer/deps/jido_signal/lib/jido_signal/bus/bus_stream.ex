defmodule Jido.Signal.Bus.Stream do
  @moduledoc """
  Provides streaming functionality for the signal bus.

  This module contains functions for filtering, processing, and publishing
  signals through the bus streaming interface. It supports operations like
  filtering signals by type pattern and timestamp, as well as publishing
  signals to subscribers.
  """

  alias Jido.Signal
  alias Jido.Signal.Bus.State, as: BusState
  alias Jido.Signal.Dispatch
  alias Jido.Signal.ID
  alias Jido.Signal.Router

  require Logger

  @doc """
  Filters signals from the bus state's log based on type pattern and timestamp.
  The type pattern is used for matching against the signal's type field.
  Ordering is determined by recorded log key chronology.
  Correlation filtering reads the canonical value from the `correlation` extension.
  """
  @spec filter(BusState.t(), String.t(), integer() | nil, keyword()) ::
          {:ok, list(Jido.Signal.Bus.RecordedSignal.t())} | {:error, atom()}
  def filter(%BusState{} = state, type_pattern, start_timestamp \\ nil, opts \\ []) do
    batch_size = Keyword.get(opts, :batch_size, 1_000)
    correlation_id = Keyword.get(opts, :correlation_id)

    # Get list of log entries from the log map in recorded order
    log_entries = BusState.log_entries_to_list(state)

    # First filter by timestamp if provided
    timestamp_filtered =
      if start_timestamp do
        filtered =
          Enum.filter(log_entries, fn {log_id, _signal} ->
            # For UUID7 IDs, we can extract the timestamp directly from the ID
            # so replay order/checkpoints are based on recorded log chronology.
            signal_ts =
              try do
                ts = ID.extract_timestamp(log_id)

                ts
              rescue
                _error ->
                  # Default to 0 for non-UUID log IDs
                  0
              end

            signal_ts > start_timestamp
          end)

        filtered
      else
        log_entries
      end

    # Then filter by correlation_id if provided
    correlation_filtered =
      if correlation_id do
        Enum.filter(timestamp_filtered, fn {_log_id, signal} ->
          correlation_id_for(signal) == correlation_id
        end)
      else
        timestamp_filtered
      end

    # Finally filter by type pattern
    # We need to check if the pattern is valid first
    case Router.Validator.validate_path(type_pattern) do
      {:ok, _} ->
        # Create a simple pattern matcher function
        matches_pattern? = fn {_log_id, signal} ->
          matches = Router.matches?(signal.type, type_pattern)

          matches
        end

        # Apply the pattern filter and take the specified batch size
        filtered_signals =
          correlation_filtered
          |> Enum.filter(matches_pattern?)
          |> Enum.take(batch_size)
          |> Enum.map(fn {log_id, signal} ->
            # Convert to RecordedSignal struct
            %Jido.Signal.Bus.RecordedSignal{
              id: log_id,
              type: signal.type,
              created_at: DateTime.utc_now(),
              signal: signal
            }
          end)

        {:ok, filtered_signals}

      {:error, reason} ->
        Logger.error("Invalid pattern: #{inspect(reason)}")
        {:error, :invalid_pattern}
    end
  rescue
    error ->
      Logger.error("Error filtering signals: #{inspect(error)}")
      {:error, :filter_failed}
  end

  @doc """
  Publishes signals to the bus, recording them and routing them to subscribers.
  Each signal is routed based on its own type field.
  Only accepts proper Jido.Signal structs to ensure system integrity.
  Signals are recorded and routed in the exact order they are received.
  """
  @spec publish(BusState.t(), list(Signal.t())) :: {:ok, BusState.t()} | {:error, atom()}
  def publish(%BusState{} = _state, []) do
    {:error, :empty_signal_list}
  end

  def publish(%BusState{} = state, signals) when is_list(signals) do
    with :ok <- validate_signals(signals),
         {:ok, new_state, _new_signals} <- BusState.append_signals(state, signals) do
      route_signals_to_subscribers(signals, new_state.subscriptions)
      {:ok, new_state}
    end
  end

  defp route_signals_to_subscribers(signals, subscriptions) do
    Enum.each(signals, fn signal ->
      dispatch_to_matching_subscriptions(signal, subscriptions)
    end)
  end

  defp dispatch_to_matching_subscriptions(signal, subscriptions) do
    Enum.each(subscriptions, fn {_id, subscription} ->
      if Router.matches?(signal.type, subscription.path) do
        Dispatch.dispatch(signal, subscription.dispatch)
      end
    end)
  end

  @doc """
  Acknowledges a signal for a given subscription.
  """
  @spec ack(BusState.t(), String.t(), Signal.t()) :: {:ok, BusState.t()} | {:error, atom()}
  def ack(%BusState{} = state, subscription_id, %Signal{} = signal) do
    case BusState.get_subscription(state, subscription_id) do
      nil ->
        {:error, :subscription_not_found}

      subscription ->
        if subscription.persistent? && subscription.persistence_pid do
          # Send ack to persistent subscription process
          GenServer.cast(subscription.persistence_pid, {:ack, signal.id})
          {:ok, state}
        else
          # Non-persistent subscriptions don't need acks
          {:ok, state}
        end
    end
  end

  @doc """
  Truncates the signal log to the specified maximum size.
  Keeps the most recent signals and discards older ones.
  """
  @spec truncate(BusState.t(), non_neg_integer()) :: {:ok, BusState.t()}
  def truncate(%BusState{} = state, max_size) when is_integer(max_size) and max_size >= 0 do
    BusState.truncate_log(state, max_size)
  end

  @doc """
  Clears all signals from the log.
  """
  @spec clear(BusState.t()) :: {:ok, BusState.t()}
  def clear(%BusState{} = state) do
    BusState.clear_log(state)
  end

  @spec validate_signals(list(term())) :: :ok | {:error, term()}
  defp validate_signals(signals) do
    invalid_signals =
      Enum.reject(signals, fn signal ->
        is_struct(signal, Signal)
      end)

    case invalid_signals do
      [] -> :ok
      _ -> {:error, :invalid_signals}
    end
  end

  defp correlation_id_for(%Signal{} = signal) do
    correlation_extension =
      Map.get(signal.extensions, "correlation") || Map.get(signal.extensions, :correlation)

    case correlation_extension do
      %{trace_id: trace_id} when is_binary(trace_id) -> trace_id
      %{"trace_id" => trace_id} when is_binary(trace_id) -> trace_id
      %{correlation_id: correlation_id} when is_binary(correlation_id) -> correlation_id
      %{"correlation_id" => correlation_id} when is_binary(correlation_id) -> correlation_id
      _ -> nil
    end
  end
end
