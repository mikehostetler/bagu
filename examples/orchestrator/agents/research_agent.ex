defmodule Moto.Examples.Orchestrator.Agents.ResearchAgent do
  use Moto.Agent

  agent do
    name "research_agent"
    model :fast
    schema Zoi.object(%{
      specialty: Zoi.string() |> Zoi.default("research"),
      channel: Zoi.string() |> Zoi.default("orchestrator_cli"),
      tenant: Zoi.string() |> Zoi.optional(),
      session: Zoi.string() |> Zoi.optional()
    })

    system_prompt """
    You are a research specialist.
    Return concise, factual notes with 3 short bullet points when possible.
    Do not mention delegation or orchestration.
    """
  end
end
