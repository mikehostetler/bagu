defmodule Jidoka.Examples.FeedbackSynthesizer.Agents.FeedbackAgent do
  @moduledoc false

  use Jidoka.Agent

  @output_schema Zoi.object(%{
                   themes: Zoi.list(Zoi.any()),
                   sentiment: Zoi.enum([:negative, :mixed, :positive]),
                   top_requests: Zoi.list(Zoi.string()),
                   risks: Zoi.list(Zoi.string()),
                   recommended_actions: Zoi.list(Zoi.string())
                 })

  agent do
    id :feedback_synthesizer_agent

    output do
      schema @output_schema
      retries(1)
      on_validation_error(:repair)
    end
  end

  defaults do
    model :fast

    instructions """
    You synthesize product feedback into themes, sentiment, risks, and actions.
    Use the fixture-backed feedback tools before producing structured output.
    """
  end

  capabilities do
    tool Jidoka.Examples.FeedbackSynthesizer.Tools.LoadFeedback
    tool Jidoka.Examples.FeedbackSynthesizer.Tools.GroupThemes
  end
end
