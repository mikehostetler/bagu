defmodule Jido.Signal.Bus.Partition do
  @moduledoc """
  A partition handles a subset of subscriptions and their dispatch.

  Partitions are used to distribute the load of signal dispatch across multiple processes.
  Each partition manages its own set of subscriptions based on a hash of the subscription ID.
  """
  use GenServer

  alias Jido.Signal.Bus.DispatchFlow
  alias Jido.Signal.Dispatch
  alias Jido.Signal.Names
  alias Jido.Signal.Router
  alias Jido.Signal.Telemetry

  require Logger

  @schema Zoi.struct(
            __MODULE__,
            %{
              partition_id: Zoi.integer(),
              bus_name: Zoi.atom(),
              bus_pid: Zoi.any(),
              subscriptions: Zoi.default(Zoi.map(), %{}) |> Zoi.optional(),
              middleware: Zoi.default(Zoi.list(), []) |> Zoi.optional(),
              middleware_timeout_ms: Zoi.default(Zoi.integer(), 100) |> Zoi.optional(),
              task_supervisor: Zoi.any() |> Zoi.nullable() |> Zoi.optional(),
              journal_adapter: Zoi.atom() |> Zoi.nullable() |> Zoi.optional(),
              journal_pid: Zoi.any() |> Zoi.nullable() |> Zoi.optional(),
              rate_limit_per_sec: Zoi.default(Zoi.integer(), 10_000) |> Zoi.optional(),
              burst_size: Zoi.default(Zoi.integer(), 1_000) |> Zoi.optional(),
              tokens: Zoi.default(Zoi.float(), 1_000.0) |> Zoi.optional(),
              last_refill: Zoi.integer() |> Zoi.nullable() |> Zoi.optional()
            }
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for Partition"
  def schema, do: @schema

  @doc """
  Starts a partition worker linked to the calling process.

  ## Options

    * `:partition_id` - The partition number (required)
    * `:bus_name` - The name of the parent bus (required)
    * `:bus_pid` - The PID of the parent bus (required)
    * `:middleware` - Middleware configurations (optional)
    * `:middleware_timeout_ms` - Timeout for middleware execution (default: 100)
    * `:journal_adapter` - Journal adapter module (optional)
    * `:journal_pid` - Journal adapter PID (optional)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    partition_id = Keyword.fetch!(opts, :partition_id)
    bus_name = Keyword.fetch!(opts, :bus_name)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(bus_name, partition_id, opts))
  end

  @doc """
  Returns a via tuple for looking up a partition by bus name and partition ID.
  """
  @spec via_tuple(atom(), non_neg_integer(), keyword()) :: {:via, Registry, {module(), tuple()}}
  def via_tuple(bus_name, partition_id, opts \\ []) do
    registry = Names.registry(opts)
    {:via, Registry, {registry, {:partition, bus_name, partition_id}}}
  end

  @doc """
  Determines which partition a subscription should be routed to.
  """
  @spec partition_for(String.t(), pos_integer()) :: non_neg_integer()
  def partition_for(subscription_id, partition_count) when partition_count > 1 do
    :erlang.phash2(subscription_id, partition_count)
  end

  def partition_for(_subscription_id, _partition_count), do: 0

  @impl GenServer
  def init(opts) do
    burst_size = Keyword.get(opts, :burst_size, 1_000)

    state = %__MODULE__{
      partition_id: Keyword.fetch!(opts, :partition_id),
      bus_name: Keyword.fetch!(opts, :bus_name),
      bus_pid: Keyword.fetch!(opts, :bus_pid),
      middleware: Keyword.get(opts, :middleware, []),
      middleware_timeout_ms: Keyword.get(opts, :middleware_timeout_ms, 100),
      task_supervisor: Keyword.get(opts, :task_supervisor, Jido.Signal.TaskSupervisor),
      journal_adapter: Keyword.get(opts, :journal_adapter),
      journal_pid: Keyword.get(opts, :journal_pid),
      rate_limit_per_sec: Keyword.get(opts, :rate_limit_per_sec, 10_000),
      burst_size: burst_size,
      tokens: burst_size * 1.0,
      last_refill: System.monotonic_time(:millisecond)
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_cast({:dispatch, signals, uuid_signal_pairs, context}, state) do
    state = refill_tokens(state)
    signal_count = length(signals)

    case consume_tokens(state, signal_count) do
      {:ok, new_state} ->
        dispatch_to_subscriptions(new_state, signals, uuid_signal_pairs, context)
        {:noreply, new_state}

      {:error, :rate_limited} ->
        Telemetry.execute(
          [:jido, :signal, :bus, :rate_limited],
          %{dropped_count: signal_count},
          %{
            bus_name: state.bus_name,
            partition_id: state.partition_id,
            available_tokens: state.tokens,
            requested: signal_count
          }
        )

        Logger.warning(
          "Partition #{state.partition_id} rate limited: dropping #{signal_count} signals " <>
            "(available: #{Float.round(state.tokens, 1)}, limit: #{state.rate_limit_per_sec}/s)"
        )

        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_call({:add_subscription, subscription_id, subscription}, _from, state) do
    new_subscriptions = Map.put(state.subscriptions, subscription_id, subscription)
    {:reply, :ok, %{state | subscriptions: new_subscriptions}}
  end

  @impl GenServer
  def handle_call({:remove_subscription, subscription_id}, _from, state) do
    new_subscriptions = Map.delete(state.subscriptions, subscription_id)
    {:reply, :ok, %{state | subscriptions: new_subscriptions}}
  end

  @impl GenServer
  def handle_call(:get_subscriptions, _from, state) do
    {:reply, {:ok, state.subscriptions}, state}
  end

  @impl GenServer
  def handle_call({:update_middleware, middleware}, _from, state) do
    {:reply, :ok, %{state | middleware: middleware}}
  end

  defp dispatch_to_subscriptions(state, signals, uuid_signal_pairs, context) do
    Enum.each(signals, fn signal ->
      dispatch_signal_to_matching_subscriptions(state, signal, uuid_signal_pairs, context)
    end)
  end

  defp dispatch_signal_to_matching_subscriptions(state, signal, uuid_signal_pairs, context) do
    Enum.each(state.subscriptions, fn {subscription_id, subscription} ->
      maybe_dispatch_to_subscription(
        state,
        signal,
        subscription,
        subscription_id,
        uuid_signal_pairs,
        context
      )
    end)
  end

  defp maybe_dispatch_to_subscription(
         state,
         signal,
         subscription,
         subscription_id,
         uuid_signal_pairs,
         context
       ) do
    # Skip persistent subscriptions - they are handled by the main bus for backpressure
    if not subscription.persistent? and Router.matches?(signal.type, subscription.path) do
      dispatch_single_signal(
        state,
        signal,
        subscription,
        subscription_id,
        uuid_signal_pairs,
        context
      )
    end
  end

  defp dispatch_single_signal(
         state,
         signal,
         subscription,
         subscription_id,
         uuid_signal_pairs,
         context
       ) do
    _ =
      DispatchFlow.dispatch(
        state.middleware,
        signal,
        subscription,
        subscription_id,
        context,
        state.middleware_timeout_ms,
        fn processed_signal, current_subscription ->
          dispatch_to_subscription(
            state,
            processed_signal,
            current_subscription,
            subscription_id,
            uuid_signal_pairs
          )
        end,
        bus_name: state.bus_name,
        partition_id: state.partition_id
      )

    :ok
  end

  defp dispatch_to_subscription(
         state,
         signal,
         subscription,
         _subscription_id,
         uuid_signal_pairs
       ) do
    if subscription.persistent? and subscription.persistence_pid do
      uuid = find_signal_uuid(signal, uuid_signal_pairs)

      try do
        GenServer.call(subscription.persistence_pid, {:signal, {uuid, signal}})
      catch
        :exit, {:noproc, _} ->
          {:error, :subscription_not_available}

        :exit, {:timeout, _} ->
          {:error, :timeout}
      end
    else
      Dispatch.dispatch(signal, subscription.dispatch, task_supervisor: state.task_supervisor)
    end
  end

  defp find_signal_uuid(signal, uuid_signal_pairs) do
    case Enum.find(uuid_signal_pairs, fn {_uuid, s} -> s.id == signal.id end) do
      {uuid, _} -> uuid
      nil -> signal.id
    end
  end

  defp refill_tokens(state) do
    now = System.monotonic_time(:millisecond)
    elapsed_ms = now - state.last_refill
    tokens_to_add = elapsed_ms / 1000.0 * state.rate_limit_per_sec

    new_tokens = min(state.burst_size * 1.0, state.tokens + tokens_to_add)

    %{state | tokens: new_tokens, last_refill: now}
  end

  defp consume_tokens(state, count) do
    if state.tokens >= count do
      {:ok, %{state | tokens: state.tokens - count}}
    else
      {:error, :rate_limited}
    end
  end
end
