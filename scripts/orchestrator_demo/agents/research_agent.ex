defmodule Moto.Scripts.OrchestratorDemo.Agents.ResearchAgent do
  use Moto.Agent

  agent do
    name "research_agent"
    model :fast

    system_prompt """
    You are a research specialist.
    Return concise, factual notes with 3 short bullet points when possible.
    Do not mention delegation or orchestration.
    """
  end

  context do
    put :specialty, "research"
    put :channel, "orchestrator_cli"
  end
end
