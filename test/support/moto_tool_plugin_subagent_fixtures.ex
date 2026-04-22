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
    id :tool_agent
  end

  defaults do
    model :fast
    instructions "You can use math tools."
  end

  capabilities do
    tool MotoTest.AddNumbers
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
    id :plugin_agent
  end

  defaults do
    model :fast
    instructions "You can use plugin-provided tools."
  end

  capabilities do
    plugin MotoTest.MathPlugin
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
    id :orchestrator_agent
  end

  defaults do
    model :fast
    instructions "You can delegate to subagents."
  end

  capabilities do
    subagent MotoTest.ResearchSpecialist

    subagent MotoTest.ReviewSpecialist,
      as: "review_specialist",
      description: "Ask the review specialist"
  end
end

defmodule MotoTest.PeerOrchestratorAgent do
  use Moto.Agent

  agent do
    id :peer_orchestrator_agent
  end

  defaults do
    model :fast
    instructions "You can delegate to a peer specialist."
  end

  capabilities do
    subagent MotoTest.ResearchSpecialist, target: {:peer, "research-peer-test"}
  end
end

defmodule MotoTest.ContextPeerOrchestratorAgent do
  use Moto.Agent

  agent do
    id :context_peer_orchestrator_agent
  end

  defaults do
    model :fast
    instructions "You can delegate to a context-derived peer specialist."
  end

  capabilities do
    subagent MotoTest.ResearchSpecialist, target: {:peer, {:context, :research_peer_id}}
  end
end

defmodule MotoTest.ContextPeerNoForwardOrchestratorAgent do
  use Moto.Agent

  agent do
    id :context_peer_no_forward_orchestrator_agent
  end

  defaults do
    model :fast
    instructions "You can delegate to a context-derived peer without forwarding context."
  end

  capabilities do
    subagent MotoTest.ResearchSpecialist,
      target: {:peer, {:context, :research_peer_id}},
      forward_context: :none
  end
end

defmodule MotoTest.WrongPeerOrchestratorAgent do
  use Moto.Agent

  agent do
    id :wrong_peer_orchestrator_agent
  end

  defaults do
    model :fast
    instructions "You expect a research specialist peer."
  end

  capabilities do
    subagent MotoTest.ResearchSpecialist, target: {:peer, "wrong-peer-test"}
  end
end

defmodule MotoTest.ForwardNoneOrchestratorAgent do
  use Moto.Agent

  agent do
    id :forward_none_orchestrator_agent
  end

  defaults do
    model :fast
    instructions "You can delegate without public context."
  end

  capabilities do
    subagent MotoTest.ResearchSpecialist, forward_context: :none
  end
end

defmodule MotoTest.ForwardOnlyOrchestratorAgent do
  use Moto.Agent

  agent do
    id :forward_only_orchestrator_agent
  end

  defaults do
    model :fast
    instructions "You can delegate with selected context."
  end

  capabilities do
    subagent MotoTest.ResearchSpecialist, forward_context: {:only, [:tenant, "notify_pid"]}
  end
end

defmodule MotoTest.ForwardExceptOrchestratorAgent do
  use Moto.Agent

  agent do
    id :forward_except_orchestrator_agent
  end

  defaults do
    model :fast
    instructions "You can delegate with excluded context."
  end

  capabilities do
    subagent MotoTest.ResearchSpecialist, forward_context: {:except, ["secret"]}
  end
end

defmodule MotoTest.StructuredOrchestratorAgent do
  use Moto.Agent

  agent do
    id :structured_orchestrator_agent
  end

  defaults do
    model :fast
    instructions "You can delegate with structured metadata."
  end

  capabilities do
    subagent MotoTest.ResearchSpecialist, result: :structured
  end
end

defmodule MotoTest.MissingPeerOrchestratorAgent do
  use Moto.Agent

  agent do
    id :missing_peer_orchestrator_agent
  end

  defaults do
    model :fast
    instructions "You expect an existing peer."
  end

  capabilities do
    subagent MotoTest.ResearchSpecialist, target: {:peer, "missing-peer-test"}
  end
end

defmodule MotoTest.SlowSpecialist do
  defmodule Runtime do
    use Jido.Agent,
      name: "slow_specialist_runtime",
      schema: Zoi.object(%{})
  end

  def name, do: "slow_agent"
  def runtime_module, do: Runtime
  def start_link(opts \\ []), do: Moto.start_agent(Runtime, opts)

  def chat(_pid, message, _opts \\ []) do
    Process.sleep(100)
    {:ok, "slow:#{message}"}
  end
end

defmodule MotoTest.TimeoutOrchestratorAgent do
  use Moto.Agent

  agent do
    id :timeout_orchestrator_agent
  end

  defaults do
    model :fast
    instructions "You can delegate to a slow specialist."
  end

  capabilities do
    subagent MotoTest.SlowSpecialist, timeout: 20
  end
end

defmodule MotoTest.InvalidResultSpecialist do
  defmodule Runtime do
    use Jido.Agent,
      name: "invalid_result_specialist_runtime",
      schema: Zoi.object(%{})
  end

  def name, do: "invalid_result_agent"
  def runtime_module, do: Runtime
  def start_link(opts \\ []), do: Moto.start_agent(Runtime, opts)
  def chat(_pid, _message, _opts \\ []), do: {:ok, %{not: "text"}}
end

defmodule MotoTest.InvalidResultOrchestratorAgent do
  use Moto.Agent

  agent do
    id :invalid_result_orchestrator_agent
  end

  defaults do
    model :fast
    instructions "You can delegate to an invalid specialist."
  end

  capabilities do
    subagent MotoTest.InvalidResultSpecialist
  end
end

defmodule MotoTest.InterruptSpecialist do
  defmodule Runtime do
    use Jido.Agent,
      name: "interrupt_specialist_runtime",
      schema: Zoi.object(%{})
  end

  def name, do: "interrupt_agent"
  def runtime_module, do: Runtime
  def start_link(opts \\ []), do: Moto.start_agent(Runtime, opts)

  def chat(_pid, _message, _opts \\ []) do
    {:interrupt, Moto.Interrupt.new(kind: :approval, message: "Need approval")}
  end
end

defmodule MotoTest.InterruptOrchestratorAgent do
  use Moto.Agent

  agent do
    id :interrupt_orchestrator_agent
  end

  defaults do
    model :fast
    instructions "You can delegate to an interrupting specialist."
  end

  capabilities do
    subagent MotoTest.InterruptSpecialist
  end
end

defmodule MotoTest.InvalidInterruptSpecialist do
  defmodule Runtime do
    use Jido.Agent,
      name: "invalid_interrupt_specialist_runtime",
      schema: Zoi.object(%{})
  end

  def name, do: "invalid_interrupt_agent"
  def runtime_module, do: Runtime
  def start_link(opts \\ []), do: Moto.start_agent(Runtime, opts)
  def chat(_pid, _message, _opts \\ []), do: {:interrupt, :not_an_interrupt}
end

defmodule MotoTest.InvalidInterruptOrchestratorAgent do
  use Moto.Agent

  agent do
    id :invalid_interrupt_orchestrator_agent
  end

  defaults do
    model :fast
    instructions "You can delegate to an invalid interrupt specialist."
  end

  capabilities do
    subagent MotoTest.InvalidInterruptSpecialist
  end
end

defmodule MotoTest.StartFailureSpecialist do
  defmodule Runtime do
    use Jido.Agent,
      name: "start_failure_specialist_runtime",
      schema: Zoi.object(%{})
  end

  def name, do: "start_failure_agent"
  def runtime_module, do: Runtime
  def start_link(_opts \\ []), do: {:error, :boom}
  def chat(_pid, _message, _opts \\ []), do: {:ok, "unreachable"}
end

defmodule MotoTest.StartFailureOrchestratorAgent do
  use Moto.Agent

  agent do
    id :start_failure_orchestrator_agent
  end

  defaults do
    model :fast
    instructions "You can delegate to a failing specialist."
  end

  capabilities do
    subagent MotoTest.StartFailureSpecialist
  end
end

defmodule MotoTest.StartIgnoreSpecialist do
  defmodule Runtime do
    use Jido.Agent,
      name: "start_ignore_specialist_runtime",
      schema: Zoi.object(%{})
  end

  def name, do: "start_ignore_agent"
  def runtime_module, do: Runtime
  def start_link(_opts \\ []), do: :ignore
  def chat(_pid, _message, _opts \\ []), do: {:ok, "unreachable"}
end

defmodule MotoTest.StartIgnoreOrchestratorAgent do
  use Moto.Agent

  agent do
    id :start_ignore_orchestrator_agent
  end

  defaults do
    model :fast
    instructions "You can delegate to an ignored specialist."
  end

  capabilities do
    subagent MotoTest.StartIgnoreSpecialist
  end
end

defmodule MotoTest.StartTripleSpecialist do
  defmodule Runtime do
    use Jido.Agent,
      name: "start_triple_specialist_runtime",
      schema: Zoi.object(%{})
  end

  def name, do: "start_triple_agent"
  def runtime_module, do: Runtime

  def start_link(opts \\ []) do
    with {:ok, pid} <- Moto.start_agent(Runtime, opts) do
      {:ok, pid, %{mode: :triple}}
    end
  end

  def chat(_pid, message, _opts \\ []), do: {:ok, "triple:#{message}"}
end

defmodule MotoTest.StartTripleOrchestratorAgent do
  use Moto.Agent

  agent do
    id :start_triple_orchestrator_agent
  end

  defaults do
    model :fast
    instructions "You can delegate to a triple-start specialist."
  end

  capabilities do
    subagent MotoTest.StartTripleSpecialist
  end
end
