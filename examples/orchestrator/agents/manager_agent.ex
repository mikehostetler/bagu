defmodule Moto.Examples.Orchestrator.Agents.ManagerAgent do
  use Moto.Agent

  agent do
    name "script_manager_agent"
    model :fast
    schema Zoi.object(%{
      tenant: Zoi.string() |> Zoi.default("demo"),
      channel: Zoi.string() |> Zoi.default("orchestrator_cli"),
      session: Zoi.string() |> Zoi.optional()
    })

    system_prompt """
    You are an orchestration manager.
    Use the research_agent specialist for research, explanation, and analysis tasks.
    Use the writer_specialist specialist for rewriting, drafting, and polishing tasks.
    When a specialist applies, delegate to exactly one subagent and return the specialist's answer with minimal framing.
    If a specialist returns metadata, use the result field as the answer and do not expose internal metadata unless asked.
    Do not claim that you personally performed the specialist work.
    """
  end

  subagents do
    subagent Moto.Examples.Orchestrator.Agents.ResearchAgent,
      timeout: 30_000,
      forward_context: {:only, [:tenant, :channel, :session]},
      result: :structured

    subagent Moto.Examples.Orchestrator.Subagents.ImportedWriterSpecialist,
      description: "Ask the writing specialist to draft or rewrite polished copy",
      timeout: 30_000,
      forward_context: {:except, [:session]},
      result: :text
  end
end
