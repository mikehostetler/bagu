defmodule Jido.Signal.Journal.Adapters.Mnesia do
  @moduledoc """
  Mnesia-based implementation of the Journal persistence behavior using Memento.

  This adapter provides durable persistence that survives node restarts.

  ## Usage

      # Ensure Mnesia schema is created (one-time setup)
      :mnesia.create_schema([node()])
      :mnesia.start()

      # Initialize tables
      :ok = Jido.Signal.Journal.Adapters.Mnesia.init()

      # Use with journal
      {:ok, journal} = Jido.Signal.Journal.new(Jido.Signal.Journal.Adapters.Mnesia)
  """

  @behaviour Jido.Signal.Journal.Persistence

  alias Jido.Signal.ID
  alias Jido.Signal.Journal.Adapters.Mnesia.Tables
  alias Jido.Signal.Telemetry

  require Logger

  @tables [
    Tables.Signal,
    Tables.Cause,
    Tables.Effect,
    Tables.Conversation,
    Tables.Checkpoint,
    Tables.DLQ
  ]

  @impl true
  def init do
    case :mnesia.system_info(:is_running) do
      :no -> :mnesia.start()
      _ -> :ok
    end

    Enum.each(@tables, fn table ->
      case Memento.Table.create(table, disc_copies: [node()]) do
        :ok ->
          :ok

        {:error, {:already_exists, _}} ->
          :ok

        {:error, reason} ->
          Logger.warning("Failed to create Mnesia table #{inspect(table)}: #{inspect(reason)}")
      end
    end)

    :mnesia.wait_for_tables(@tables, 5000)

    :ok
  end

  @impl true
  def put_signal(signal, _pid) do
    start_time = System.monotonic_time(:microsecond)

    result =
      Memento.transaction(fn ->
        Memento.Query.write(%Tables.Signal{id: signal.id, signal: signal})
      end)

    duration_us = System.monotonic_time(:microsecond) - start_time
    emit_telemetry(:put_signal, duration_us)

    case result do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def get_signal(signal_id, _pid) do
    start_time = System.monotonic_time(:microsecond)

    result =
      Memento.transaction(fn ->
        Memento.Query.read(Tables.Signal, signal_id)
      end)

    duration_us = System.monotonic_time(:microsecond) - start_time
    emit_telemetry(:get_signal, duration_us)

    case result do
      {:ok, nil} -> {:error, :not_found}
      {:ok, %Tables.Signal{signal: signal}} -> {:ok, signal}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def put_cause(cause_id, effect_id, _pid) do
    start_time = System.monotonic_time(:microsecond)

    result =
      Memento.transaction(fn ->
        effects =
          case Memento.Query.read(Tables.Cause, cause_id) do
            nil -> MapSet.new([effect_id])
            %Tables.Cause{effects: existing} -> MapSet.put(existing, effect_id)
          end

        Memento.Query.write(%Tables.Cause{cause_id: cause_id, effects: effects})

        causes =
          case Memento.Query.read(Tables.Effect, effect_id) do
            nil -> MapSet.new([cause_id])
            %Tables.Effect{causes: existing} -> MapSet.put(existing, cause_id)
          end

        Memento.Query.write(%Tables.Effect{effect_id: effect_id, causes: causes})
      end)

    duration_us = System.monotonic_time(:microsecond) - start_time
    emit_telemetry(:put_cause, duration_us)

    case result do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def get_effects(signal_id, _pid) do
    start_time = System.monotonic_time(:microsecond)

    result =
      Memento.transaction(fn ->
        case Memento.Query.read(Tables.Cause, signal_id) do
          nil -> MapSet.new()
          %Tables.Cause{effects: effects} -> effects
        end
      end)

    duration_us = System.monotonic_time(:microsecond) - start_time
    emit_telemetry(:get_effects, duration_us)

    case result do
      {:ok, effects} -> {:ok, effects}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def get_cause(signal_id, _pid) do
    start_time = System.monotonic_time(:microsecond)

    result =
      Memento.transaction(fn ->
        extract_cause_id(signal_id)
      end)

    duration_us = System.monotonic_time(:microsecond) - start_time
    emit_telemetry(:get_cause, duration_us)

    case result do
      {:ok, nil} -> {:error, :not_found}
      {:ok, cause_id} -> {:ok, cause_id}
      {:error, reason} -> {:error, reason}
    end
  end

  defp extract_cause_id(signal_id) do
    case Memento.Query.read(Tables.Effect, signal_id) do
      nil -> nil
      %Tables.Effect{causes: causes} -> first_cause_id(causes)
    end
  end

  defp first_cause_id(causes) do
    case MapSet.to_list(causes) do
      [cause_id | _] -> cause_id
      [] -> nil
    end
  end

  @impl true
  def put_conversation(conversation_id, signal_id, _pid) do
    start_time = System.monotonic_time(:microsecond)

    result =
      Memento.transaction(fn ->
        signals =
          case Memento.Query.read(Tables.Conversation, conversation_id) do
            nil -> MapSet.new([signal_id])
            %Tables.Conversation{signals: existing} -> MapSet.put(existing, signal_id)
          end

        Memento.Query.write(%Tables.Conversation{
          conversation_id: conversation_id,
          signals: signals
        })
      end)

    duration_us = System.monotonic_time(:microsecond) - start_time
    emit_telemetry(:put_conversation, duration_us)

    case result do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def get_conversation(conversation_id, _pid) do
    start_time = System.monotonic_time(:microsecond)

    result =
      Memento.transaction(fn ->
        case Memento.Query.read(Tables.Conversation, conversation_id) do
          nil -> MapSet.new()
          %Tables.Conversation{signals: signals} -> signals
        end
      end)

    duration_us = System.monotonic_time(:microsecond) - start_time
    emit_telemetry(:get_conversation, duration_us)

    case result do
      {:ok, signals} -> {:ok, signals}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def put_checkpoint(subscription_id, checkpoint, _pid) do
    start_time = System.monotonic_time(:microsecond)

    result =
      Memento.transaction(fn ->
        Memento.Query.write(%Tables.Checkpoint{
          subscription_id: subscription_id,
          checkpoint: checkpoint
        })
      end)

    duration_us = System.monotonic_time(:microsecond) - start_time
    emit_telemetry(:put_checkpoint, duration_us)

    case result do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def get_checkpoint(subscription_id, _pid) do
    start_time = System.monotonic_time(:microsecond)

    result =
      Memento.transaction(fn ->
        Memento.Query.read(Tables.Checkpoint, subscription_id)
      end)

    duration_us = System.monotonic_time(:microsecond) - start_time
    emit_telemetry(:get_checkpoint, duration_us)

    case result do
      {:ok, nil} -> {:error, :not_found}
      {:ok, %Tables.Checkpoint{checkpoint: checkpoint}} -> {:ok, checkpoint}
      {:error, reason} -> {:error, reason}
    end
  end

  @dialyzer {:nowarn_function, delete_checkpoint: 2}
  @impl true
  def delete_checkpoint(subscription_id, _pid) do
    start_time = System.monotonic_time(:microsecond)

    result =
      Memento.transaction(fn ->
        Memento.Query.delete(Tables.Checkpoint, subscription_id)
      end)

    duration_us = System.monotonic_time(:microsecond) - start_time
    emit_telemetry(:delete_checkpoint, duration_us)

    case result do
      :ok -> :ok
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def put_dlq_entry(subscription_id, signal, reason, metadata, _pid) do
    start_time = System.monotonic_time(:microsecond)
    entry_id = ID.generate!()
    inserted_at = DateTime.utc_now()

    result =
      Memento.transaction(fn ->
        Memento.Query.write(%Tables.DLQ{
          id: entry_id,
          subscription_id: subscription_id,
          signal: signal,
          reason: reason,
          metadata: metadata,
          inserted_at: inserted_at
        })
      end)

    duration_us = System.monotonic_time(:microsecond) - start_time
    emit_telemetry(:put_dlq_entry, duration_us)

    Telemetry.execute(
      [:jido, :signal, :journal, :dlq, :put],
      %{},
      %{subscription_id: subscription_id, entry_id: entry_id}
    )

    case result do
      {:ok, _} -> {:ok, entry_id}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def get_dlq_entries(subscription_id, _pid) do
    start_time = System.monotonic_time(:microsecond)

    result =
      Memento.transaction(fn ->
        Memento.Query.select(Tables.DLQ, {:==, :subscription_id, subscription_id})
      end)

    duration_us = System.monotonic_time(:microsecond) - start_time
    emit_telemetry(:get_dlq_entries, duration_us)

    case result do
      {:ok, records} ->
        entries =
          records
          |> Enum.map(fn %Tables.DLQ{
                           id: id,
                           subscription_id: sub_id,
                           signal: signal,
                           reason: reason,
                           metadata: metadata,
                           inserted_at: inserted_at
                         } ->
            %{
              id: id,
              subscription_id: sub_id,
              signal: signal,
              reason: reason,
              metadata: metadata,
              inserted_at: inserted_at
            }
          end)
          |> Enum.sort_by(fn entry -> entry.inserted_at end, DateTime)

        Telemetry.execute(
          [:jido, :signal, :journal, :dlq, :get],
          %{count: length(entries)},
          %{subscription_id: subscription_id}
        )

        {:ok, entries}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @dialyzer {:nowarn_function, delete_dlq_entry: 2}
  @impl true
  def delete_dlq_entry(entry_id, _pid) do
    start_time = System.monotonic_time(:microsecond)

    result =
      Memento.transaction(fn ->
        Memento.Query.delete(Tables.DLQ, entry_id)
      end)

    duration_us = System.monotonic_time(:microsecond) - start_time
    emit_telemetry(:delete_dlq_entry, duration_us)

    case result do
      :ok -> :ok
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @dialyzer {:nowarn_function, clear_dlq: 2}
  @impl true
  def clear_dlq(subscription_id, _pid) do
    start_time = System.monotonic_time(:microsecond)

    result =
      Memento.transaction(fn ->
        records = Memento.Query.select(Tables.DLQ, {:==, :subscription_id, subscription_id})

        Enum.each(records, fn record ->
          Memento.Query.delete(Tables.DLQ, record.id)
        end)
      end)

    duration_us = System.monotonic_time(:microsecond) - start_time
    emit_telemetry(:clear_dlq, duration_us)

    case result do
      :ok -> :ok
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp emit_telemetry(operation, duration_us) do
    Telemetry.execute(
      [:jido, :signal, :journal, :mnesia, :operation],
      %{duration_us: duration_us},
      %{operation: operation}
    )
  end
end
