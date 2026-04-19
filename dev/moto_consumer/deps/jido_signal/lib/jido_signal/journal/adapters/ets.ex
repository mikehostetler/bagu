defmodule Jido.Signal.Journal.Adapters.ETS do
  @moduledoc """
  ETS-based implementation of the Journal persistence behavior.
  Uses separate ETS tables for signals, causes, effects, and conversations.

  ## Configuration
  The adapter requires a prefix for table names to allow multiple instances:

      {:ok, _pid} = Jido.Signal.Journal.Adapters.ETS.start_link("my_journal_")
      {:ok, journal} = Jido.Signal.Journal.new(Jido.Signal.Journal.Adapters.ETS)

  This will create tables with names:
    - :my_journal_signals
    - :my_journal_causes
    - :my_journal_effects
    - :my_journal_conversations
  """
  @behaviour Jido.Signal.Journal.Persistence

  use GenServer

  alias Jido.Signal.ID
  alias Jido.Signal.Telemetry

  @schema Zoi.struct(
            __MODULE__,
            %{
              signals_table: Zoi.any() |> Zoi.nullable() |> Zoi.optional(),
              causes_table: Zoi.any() |> Zoi.nullable() |> Zoi.optional(),
              effects_table: Zoi.any() |> Zoi.nullable() |> Zoi.optional(),
              conversations_table: Zoi.any() |> Zoi.nullable() |> Zoi.optional(),
              checkpoints_table: Zoi.any() |> Zoi.nullable() |> Zoi.optional(),
              dlq_table: Zoi.any() |> Zoi.nullable() |> Zoi.optional()
            }
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for ETS adapter"
  def schema, do: @schema

  # Client API

  @doc """
  Starts the ETS adapter with the given table name prefix.
  """
  def start_link(prefix) when is_binary(prefix) do
    GenServer.start_link(__MODULE__, prefix)
  end

  @impl Jido.Signal.Journal.Persistence
  def init do
    # Generate a unique prefix for this instance
    prefix = "journal_#{System.unique_integer([:positive, :monotonic])}_"

    case start_link(prefix) do
      {:ok, pid} -> {:ok, pid}
      error -> error
    end
  end

  @impl Jido.Signal.Journal.Persistence
  def put_signal(signal, pid) do
    GenServer.call(pid, {:put_signal, signal})
  end

  @impl Jido.Signal.Journal.Persistence
  def get_signal(signal_id, pid) do
    GenServer.call(pid, {:get_signal, signal_id})
  end

  @impl Jido.Signal.Journal.Persistence
  def put_cause(cause_id, effect_id, pid) do
    GenServer.call(pid, {:put_cause, cause_id, effect_id})
  end

  @impl Jido.Signal.Journal.Persistence
  def get_effects(signal_id, pid) do
    GenServer.call(pid, {:get_effects, signal_id})
  end

  @impl Jido.Signal.Journal.Persistence
  def get_cause(signal_id, pid) do
    GenServer.call(pid, {:get_cause, signal_id})
  end

  @impl Jido.Signal.Journal.Persistence
  def put_conversation(conversation_id, signal_id, pid) do
    GenServer.call(pid, {:put_conversation, conversation_id, signal_id})
  end

  @impl Jido.Signal.Journal.Persistence
  def get_conversation(conversation_id, pid) do
    GenServer.call(pid, {:get_conversation, conversation_id})
  end

  @impl Jido.Signal.Journal.Persistence
  def put_checkpoint(subscription_id, checkpoint, pid) do
    GenServer.call(pid, {:put_checkpoint, subscription_id, checkpoint})
  end

  @impl Jido.Signal.Journal.Persistence
  def get_checkpoint(subscription_id, pid) do
    GenServer.call(pid, {:get_checkpoint, subscription_id})
  end

  @impl Jido.Signal.Journal.Persistence
  def delete_checkpoint(subscription_id, pid) do
    GenServer.call(pid, {:delete_checkpoint, subscription_id})
  end

  @impl Jido.Signal.Journal.Persistence
  def put_dlq_entry(subscription_id, signal, reason, metadata, pid) do
    GenServer.call(pid, {:put_dlq_entry, subscription_id, signal, reason, metadata})
  end

  @impl Jido.Signal.Journal.Persistence
  def get_dlq_entries(subscription_id, pid) do
    GenServer.call(pid, {:get_dlq_entries, subscription_id})
  end

  @impl Jido.Signal.Journal.Persistence
  def delete_dlq_entry(entry_id, pid) do
    GenServer.call(pid, {:delete_dlq_entry, entry_id})
  end

  @impl Jido.Signal.Journal.Persistence
  def clear_dlq(subscription_id, pid) do
    GenServer.call(pid, {:clear_dlq, subscription_id})
  end

  @doc """
  Gets all signals in the journal.
  """
  def get_all_signals(pid) do
    GenServer.call(pid, :get_all_signals)
  end

  @doc """
  Cleans up all ETS tables used by this adapter instance.

  Returns `:ok` if the adapter process is already gone.
  """
  def cleanup(pid_or_name) do
    case GenServer.whereis(pid_or_name) do
      nil ->
        :ok

      _pid ->
        try do
          GenServer.call(pid_or_name, :cleanup)
        catch
          :exit, :noproc -> :ok
          :exit, {:noproc, _} -> :ok
          :exit, :normal -> :ok
          :exit, :shutdown -> :ok
          :exit, {:shutdown, _} -> :ok
        end
    end
  end

  # Server Callbacks

  @doc """
  Initializes the ETS adapter with the given table name prefix.

  ## Parameters

  - `prefix`: The prefix to use for table names

  ## Returns

  - `{:ok, adapter}` if initialization succeeds
  - `{:error, reason}` if initialization fails

  ## Examples

      iex> {:ok, adapter} = Jido.Signal.Journal.Adapters.ETS.init("my_journal_")
      iex> adapter.signals_table
      :my_journal_signals_...
  """
  @spec init(String.t()) :: {:ok, t()} | {:error, term()}
  @impl GenServer
  def init(_prefix) do
    adapter = %__MODULE__{
      signals_table: :ets.new(:signals, [:set, :public]),
      causes_table: :ets.new(:causes, [:set, :public]),
      effects_table: :ets.new(:effects, [:set, :public]),
      conversations_table: :ets.new(:conversations, [:set, :public]),
      checkpoints_table: :ets.new(:checkpoints, [:set, :public]),
      dlq_table: :ets.new(:dlq, [:set, :public])
    }

    {:ok, adapter}
  end

  @doc """
  Handles GenServer calls for signal operations.

  ## Parameters

  - `{:put_signal, signal}` - Stores a signal in the journal
  - `{:get_signal, signal_id}` - Retrieves a signal by ID
  - `{:put_cause, cause_id, effect_id}` - Records a cause-effect relationship
  - `{:get_effects, signal_id}` - Gets all effects for a signal
  - `{:get_cause, signal_id}` - Gets the cause for a signal
  - `{:put_conversation, conversation_id, signal_id}` - Adds a signal to a conversation
  - `{:get_conversation, conversation_id}` - Gets all signals in a conversation
  - `:get_all_signals` - Gets all signals in the journal
  - `:cleanup` - Cleans up all ETS tables

  ## Returns

  - `{:reply, result, adapter}` for successful operations
  - `{:reply, {:error, reason}, adapter}` for failed operations
  """
  @spec handle_call(term(), {pid(), term()}, t()) :: {:reply, term(), t()}
  @impl GenServer
  def handle_call({:put_signal, signal}, _from, adapter) do
    true = :ets.insert(adapter.signals_table, {signal.id, signal})
    {:reply, :ok, adapter}
  end

  @impl GenServer
  def handle_call({:get_signal, signal_id}, _from, adapter) do
    reply =
      case :ets.lookup(adapter.signals_table, signal_id) do
        [{^signal_id, signal}] -> {:ok, signal}
        [] -> {:error, :not_found}
      end

    {:reply, reply, adapter}
  end

  @impl GenServer
  def handle_call({:put_cause, cause_id, effect_id}, _from, adapter) do
    # Update causes
    effects =
      case :ets.lookup(adapter.causes_table, cause_id) do
        [{^cause_id, existing}] -> MapSet.put(existing, effect_id)
        [] -> MapSet.new([effect_id])
      end

    true = :ets.insert(adapter.causes_table, {cause_id, effects})

    # Update effects
    causes =
      case :ets.lookup(adapter.effects_table, effect_id) do
        [{^effect_id, existing}] -> MapSet.put(existing, cause_id)
        [] -> MapSet.new([cause_id])
      end

    true = :ets.insert(adapter.effects_table, {effect_id, causes})
    {:reply, :ok, adapter}
  end

  @impl GenServer
  def handle_call({:get_effects, signal_id}, _from, adapter) do
    effects =
      case :ets.lookup(adapter.causes_table, signal_id) do
        [{^signal_id, effects}] -> effects
        [] -> MapSet.new()
      end

    {:reply, {:ok, effects}, adapter}
  end

  @impl GenServer
  def handle_call({:get_cause, signal_id}, _from, adapter) do
    reply =
      case :ets.lookup(adapter.effects_table, signal_id) do
        [{^signal_id, causes}] ->
          case MapSet.to_list(causes) do
            [cause_id | _] -> {:ok, cause_id}
            [] -> {:error, :not_found}
          end

        [] ->
          {:error, :not_found}
      end

    {:reply, reply, adapter}
  end

  @impl GenServer
  def handle_call({:put_conversation, conversation_id, signal_id}, _from, adapter) do
    signals =
      case :ets.lookup(adapter.conversations_table, conversation_id) do
        [{^conversation_id, existing}] -> MapSet.put(existing, signal_id)
        [] -> MapSet.new([signal_id])
      end

    true = :ets.insert(adapter.conversations_table, {conversation_id, signals})
    {:reply, :ok, adapter}
  end

  @impl GenServer
  def handle_call({:get_conversation, conversation_id}, _from, adapter) do
    signals =
      case :ets.lookup(adapter.conversations_table, conversation_id) do
        [{^conversation_id, signals}] -> signals
        [] -> MapSet.new()
      end

    {:reply, {:ok, signals}, adapter}
  end

  @impl GenServer
  def handle_call({:put_checkpoint, subscription_id, checkpoint}, _from, adapter) do
    Telemetry.execute(
      [:jido, :signal, :journal, :checkpoint, :put],
      %{},
      %{subscription_id: subscription_id}
    )

    true = :ets.insert(adapter.checkpoints_table, {subscription_id, checkpoint})
    {:reply, :ok, adapter}
  end

  @impl GenServer
  def handle_call({:get_checkpoint, subscription_id}, _from, adapter) do
    reply =
      case :ets.lookup(adapter.checkpoints_table, subscription_id) do
        [{^subscription_id, checkpoint}] ->
          Telemetry.execute(
            [:jido, :signal, :journal, :checkpoint, :get],
            %{},
            %{subscription_id: subscription_id, found: true}
          )

          {:ok, checkpoint}

        [] ->
          Telemetry.execute(
            [:jido, :signal, :journal, :checkpoint, :get],
            %{},
            %{subscription_id: subscription_id, found: false}
          )

          {:error, :not_found}
      end

    {:reply, reply, adapter}
  end

  @impl GenServer
  def handle_call({:delete_checkpoint, subscription_id}, _from, adapter) do
    :ets.delete(adapter.checkpoints_table, subscription_id)
    {:reply, :ok, adapter}
  end

  @impl GenServer
  def handle_call({:put_dlq_entry, subscription_id, signal, reason, metadata}, _from, adapter) do
    entry_id = ID.generate!()

    entry = %{
      id: entry_id,
      subscription_id: subscription_id,
      signal: signal,
      reason: reason,
      metadata: metadata,
      inserted_at: DateTime.utc_now()
    }

    true = :ets.insert(adapter.dlq_table, {entry_id, entry})

    Telemetry.execute(
      [:jido, :signal, :journal, :dlq, :put],
      %{},
      %{subscription_id: subscription_id, entry_id: entry_id}
    )

    {:reply, {:ok, entry_id}, adapter}
  end

  @impl GenServer
  def handle_call({:get_dlq_entries, subscription_id}, _from, adapter) do
    entries =
      :ets.select(adapter.dlq_table, [
        {{:_, :"$1"}, [{:==, {:map_get, :subscription_id, :"$1"}, subscription_id}], [:"$1"]}
      ])
      |> Enum.sort_by(fn entry -> entry.inserted_at end, DateTime)

    Telemetry.execute(
      [:jido, :signal, :journal, :dlq, :get],
      %{count: length(entries)},
      %{subscription_id: subscription_id}
    )

    {:reply, {:ok, entries}, adapter}
  end

  @impl GenServer
  def handle_call({:delete_dlq_entry, entry_id}, _from, adapter) do
    :ets.delete(adapter.dlq_table, entry_id)
    {:reply, :ok, adapter}
  end

  @impl GenServer
  def handle_call({:clear_dlq, subscription_id}, _from, adapter) do
    :ets.select_delete(adapter.dlq_table, [
      {{:_, :"$1"}, [{:==, {:map_get, :subscription_id, :"$1"}, subscription_id}], [true]}
    ])

    {:reply, :ok, adapter}
  end

  @impl GenServer
  def handle_call(:get_all_signals, _from, adapter) do
    signals =
      :ets.tab2list(adapter.signals_table)
      |> Enum.map(fn {_id, signal} -> signal end)

    {:reply, signals, adapter}
  end

  @impl GenServer
  def handle_call(:cleanup, _from, adapter) do
    [
      adapter.signals_table,
      adapter.causes_table,
      adapter.effects_table,
      adapter.conversations_table,
      adapter.checkpoints_table,
      adapter.dlq_table
    ]
    |> Enum.each(fn table ->
      case :ets.info(table) do
        :undefined ->
          :ok

        _info ->
          :ets.delete(table)
      end
    end)

    {:reply, :ok, adapter}
  end
end
