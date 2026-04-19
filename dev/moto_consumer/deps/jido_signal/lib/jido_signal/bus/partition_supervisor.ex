defmodule Jido.Signal.Bus.PartitionSupervisor do
  @moduledoc """
  Supervises partition workers for a bus.

  Each bus with partition_count > 1 will have a PartitionSupervisor that manages
  the partition workers. This enables horizontal scaling of signal dispatch.
  """
  use Supervisor

  alias Jido.Signal.Names
  alias Jido.Signal.Bus.Partition

  @doc """
  Starts the partition supervisor.

  ## Options

    * `:bus_name` - The name of the parent bus (required)
    * `:bus_pid` - The PID of the parent bus (required)
    * `:partition_count` - Number of partitions to create (default: 1)
    * `:middleware` - Middleware configurations (optional)
    * `:middleware_timeout_ms` - Timeout for middleware execution (default: 100)
    * `:journal_adapter` - Journal adapter module (optional)
    * `:journal_pid` - Journal adapter PID (optional)
  """
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    bus_name = Keyword.fetch!(opts, :bus_name)
    Supervisor.start_link(__MODULE__, opts, name: via_tuple(bus_name, opts))
  end

  @doc """
  Returns a via tuple for looking up a partition supervisor by bus name.
  """
  @spec via_tuple(atom(), keyword()) :: {:via, Registry, {module(), tuple()}}
  def via_tuple(bus_name, opts \\ []) do
    registry = Names.registry(opts)
    {:via, Registry, {registry, {:partition_supervisor, bus_name}}}
  end

  @impl Supervisor
  def init(opts) do
    partition_count = Keyword.get(opts, :partition_count, 1)
    bus_name = Keyword.fetch!(opts, :bus_name)
    bus_pid = Keyword.fetch!(opts, :bus_pid)
    jido = Keyword.get(opts, :jido)
    middleware = Keyword.get(opts, :middleware, [])
    middleware_timeout_ms = Keyword.get(opts, :middleware_timeout_ms, 100)
    task_supervisor = Names.task_supervisor(jido: jido)
    journal_adapter = Keyword.get(opts, :journal_adapter)
    journal_pid = Keyword.get(opts, :journal_pid)
    rate_limit_per_sec = Keyword.get(opts, :rate_limit_per_sec, 10_000)
    burst_size = Keyword.get(opts, :burst_size, 1_000)

    children =
      for i <- 0..(partition_count - 1) do
        Supervisor.child_spec(
          {Partition,
           [
             partition_id: i,
             bus_name: bus_name,
             bus_pid: bus_pid,
             jido: jido,
             middleware: middleware,
             middleware_timeout_ms: middleware_timeout_ms,
             task_supervisor: task_supervisor,
             journal_adapter: journal_adapter,
             journal_pid: journal_pid,
             rate_limit_per_sec: rate_limit_per_sec,
             burst_size: burst_size
           ]},
          id: {Partition, i}
        )
      end

    Supervisor.init(children, strategy: :one_for_one)
  end
end
