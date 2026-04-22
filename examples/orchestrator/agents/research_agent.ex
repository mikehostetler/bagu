defmodule Moto.Examples.Orchestrator.Agents.ResearchAgent do
  use Moto.Agent

  @context_fields %{
    specialty: Zoi.string() |> Zoi.default("research"),
    channel: Zoi.string() |> Zoi.default("orchestrator_cli"),
    tenant: Zoi.string() |> Zoi.optional(),
    session: Zoi.string() |> Zoi.optional()
  }

  agent do
    id :research_agent

    schema Zoi.object(@context_fields)
  end

  defaults do
    model :fast

    instructions """
    You are a research specialist.
    Return concise, factual notes with 3 short bullet points when possible.
    Do not mention delegation or orchestration.
    """
  end
end
