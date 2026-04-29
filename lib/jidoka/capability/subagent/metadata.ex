defmodule Jidoka.Subagent.Metadata do
  @moduledoc false

  use GenServer

  @table :jidoka_subagent_calls
  @ttl_ms 15 * 60 * 1_000
  @prune_interval_ms 60 * 1_000

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec insert(pid(), String.t(), map()) :: :ok
  def insert(parent_server, request_id, metadata)
      when is_pid(parent_server) and is_binary(request_id) and is_map(metadata) do
    ensure_table()
    now = monotonic_ms()
    :ets.insert(@table, {{parent_server, request_id}, Map.put(metadata, :recorded_at_ms, now)})
    :ok
  end

  def insert(_parent_server, _request_id, _metadata), do: :ok

  @spec drain(pid(), String.t()) :: [map()]
  def drain(parent_server, request_id) when is_pid(parent_server) and is_binary(request_id) do
    ensure_table()

    @table
    |> :ets.take({parent_server, request_id})
    |> Enum.map(fn {{^parent_server, ^request_id}, metadata} -> strip_runtime_meta(metadata) end)
  end

  def drain(_parent_server, _request_id), do: []

  @spec lookup(pid(), String.t()) :: [map()]
  def lookup(parent_server, request_id) when is_pid(parent_server) and is_binary(request_id) do
    ensure_table()

    @table
    |> :ets.lookup({parent_server, request_id})
    |> Enum.map(fn {{^parent_server, ^request_id}, metadata} -> strip_runtime_meta(metadata) end)
  end

  def lookup(_parent_server, _request_id), do: []

  @impl true
  def init(_opts) do
    ensure_table()
    schedule_prune()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:prune_stale, state) do
    prune_stale(monotonic_ms())
    schedule_prune()
    {:noreply, state}
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [:bag, :public, :named_table, read_concurrency: true])

      _table ->
        @table
    end
  rescue
    ArgumentError -> @table
  end

  defp prune_stale(now) do
    cutoff = now - @ttl_ms

    @table
    |> :ets.tab2list()
    |> Enum.each(fn
      {key, %{recorded_at_ms: recorded_at_ms} = metadata} when recorded_at_ms < cutoff ->
        :ets.delete_object(@table, {key, metadata})

      _entry ->
        :ok
    end)
  end

  defp strip_runtime_meta(metadata), do: Map.delete(metadata, :recorded_at_ms)
  defp monotonic_ms, do: System.monotonic_time(:millisecond)
  defp schedule_prune, do: Process.send_after(self(), :prune_stale, @prune_interval_ms)
end
