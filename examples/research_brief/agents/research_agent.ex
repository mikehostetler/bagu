defmodule Jidoka.Examples.ResearchBrief.Agents.ResearchAgent do
  @moduledoc false

  use Jidoka.Agent

  @output_schema Zoi.object(%{
                   brief: Zoi.string(),
                   key_points: Zoi.list(Zoi.string()),
                   sources: Zoi.list(Zoi.any()),
                   open_questions: Zoi.list(Zoi.string())
                 })

  agent do
    id :research_brief_agent

    output do
      schema @output_schema
      retries(1)
      on_validation_error(:repair)
    end
  end

  defaults do
    model :fast

    instructions """
    You create source-aware research briefs.
    Use retrieval tools and keep each key point tied to source ids.
    """
  end

  capabilities do
    tool Jidoka.Examples.ResearchBrief.Tools.LoadSources
    tool Jidoka.Examples.ResearchBrief.Tools.RankSources
  end

  lifecycle do
    output_guardrail Jidoka.Examples.ResearchBrief.Guardrails.RequireSources
  end
end
