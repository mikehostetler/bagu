defmodule MotoTest.AddNumbers do
  use Moto.Tool,
    description: "Adds two integers together.",
    schema: Zoi.object(%{a: Zoi.integer(), b: Zoi.integer()})

  @impl true
  def run(%{a: a, b: b}, _context) do
    {:ok, %{sum: a + b}}
  end
end

defmodule MotoTest.MultiplyNumbers do
  use Moto.Tool,
    description: "Multiplies two integers together.",
    schema: Zoi.object(%{a: Zoi.integer(), b: Zoi.integer()})

  @impl true
  def run(%{a: a, b: b}, _context) do
    {:ok, %{product: a * b}}
  end
end

defmodule MotoTest.ToolAgent do
  use Moto.Agent

  agent do
    model(:fast)
    system_prompt("You can use math tools.")
  end

  tools do
    tool(MotoTest.AddNumbers)
  end
end

defmodule MotoTest.MathPlugin do
  use Moto.Plugin,
    description: "Provides math tools for Moto agents.",
    tools: [MotoTest.MultiplyNumbers]
end

defmodule MotoTest.PluginAgent do
  use Moto.Agent

  agent do
    model(:fast)
    system_prompt("You can use plugin-provided tools.")
  end

  plugins do
    plugin(MotoTest.MathPlugin)
  end
end

defmodule MotoTest.ResearchSpecialist do
  defmodule Runtime do
    use Jido.Agent,
      name: "research_specialist_runtime",
      schema: Zoi.object(%{})
  end

  def name, do: "research_agent"
  def runtime_module, do: Runtime
  def start_link(opts \\ []), do: Moto.start_agent(Runtime, opts)

  def chat(_pid, message, opts \\ []) do
    context = Keyword.get(opts, :context, %{})

    if notify_pid = Map.get(context, :notify_pid, Map.get(context, "notify_pid")) do
      send(notify_pid, {:research_specialist_context, context})
    end

    tenant = Map.get(context, :tenant, Map.get(context, "tenant", "none"))
    depth = Map.get(context, Moto.Subagent.depth_key(), 0)

    {:ok, "research:#{message}:tenant=#{tenant}:depth=#{depth}"}
  end
end

defmodule MotoTest.ReviewSpecialist do
  defmodule Runtime do
    use Jido.Agent,
      name: "review_specialist_runtime",
      schema: Zoi.object(%{})
  end

  def name, do: "review_agent"
  def runtime_module, do: Runtime
  def start_link(opts \\ []), do: Moto.start_agent(Runtime, opts)
  def chat(_pid, message, _opts \\ []), do: {:ok, "review:#{message}"}
end

defmodule MotoTest.OrchestratorAgent do
  use Moto.Agent

  agent do
    model(:fast)
    system_prompt("You can delegate to subagents.")
  end

  subagents do
    subagent(MotoTest.ResearchSpecialist)

    subagent(MotoTest.ReviewSpecialist,
      as: "review_specialist",
      description: "Ask the review specialist"
    )
  end
end

defmodule MotoTest.PeerOrchestratorAgent do
  use Moto.Agent

  agent do
    model(:fast)
    system_prompt("You can delegate to a peer specialist.")
  end

  subagents do
    subagent(MotoTest.ResearchSpecialist, target: {:peer, "research-peer-test"})
  end
end

defmodule MotoTest.ContextPeerOrchestratorAgent do
  use Moto.Agent

  agent do
    model(:fast)
    system_prompt("You can delegate to a context-derived peer specialist.")
  end

  subagents do
    subagent(MotoTest.ResearchSpecialist, target: {:peer, {:context, :research_peer_id}})
  end
end

defmodule MotoTest.WrongPeerOrchestratorAgent do
  use Moto.Agent

  agent do
    model(:fast)
    system_prompt("You expect a research specialist peer.")
  end

  subagents do
    subagent(MotoTest.ResearchSpecialist, target: {:peer, "wrong-peer-test"})
  end
end
