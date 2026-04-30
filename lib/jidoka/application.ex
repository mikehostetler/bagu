defmodule Jidoka.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Jidoka.Trace.Collector,
      {Task.Supervisor, name: Jidoka.Schedule.TaskSupervisor},
      Jidoka.Schedule.Manager,
      Jidoka.Subagent.Metadata,
      Jidoka.Workflow.Capability.Metadata,
      Jidoka.Handoff.Metadata,
      Jidoka.Handoff.Registry,
      Jidoka.Runtime
    ]

    opts = [strategy: :one_for_one, name: Jidoka.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
