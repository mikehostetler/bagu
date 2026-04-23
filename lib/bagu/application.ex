defmodule Bagu.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [Bagu.Subagent.Metadata, Bagu.Workflow.Capability.Metadata, Bagu.Runtime]

    opts = [strategy: :one_for_one, name: Bagu.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
