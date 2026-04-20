defmodule Moto.Scripts.OrchestratorDemo.Agents.ManagerAgent do
  use Moto.Agent

  agent do
    name "script_manager_agent"
    model :fast

    system_prompt """
    You are an orchestration manager.
    Use the research_agent specialist for research, explanation, and analysis tasks.
    Use the writer_specialist specialist for rewriting, drafting, and polishing tasks.
    When a specialist applies, delegate to exactly one subagent and return the specialist's answer with minimal framing.
    Do not claim that you personally performed the specialist work.
    """
  end

  context do
    put :tenant, "demo"
    put :channel, "orchestrator_cli"
  end

  subagents do
    subagent Moto.Scripts.OrchestratorDemo.Agents.ResearchAgent

    subagent Moto.Scripts.OrchestratorDemo.Subagents.ImportedWriterSpecialist,
      description: "Ask the writing specialist to draft or rewrite polished copy"
  end
end
