defmodule Jidoka.Examples.PrReviewer.Agents.ReviewerAgent do
  @moduledoc false

  use Jidoka.Agent

  @output_schema Zoi.object(%{
                   summary: Zoi.string(),
                   findings: Zoi.list(Zoi.any()),
                   test_gaps: Zoi.list(Zoi.string()),
                   recommended_next_steps: Zoi.list(Zoi.string())
                 })

  agent do
    id :pr_reviewer_agent

    output do
      schema @output_schema
      retries(1)
      on_validation_error(:repair)
    end
  end

  defaults do
    model :fast

    instructions """
    You review pull request diffs.
    Prioritize bugs, regressions, security risks, and missing tests over style feedback.
    """
  end

  capabilities do
    tool Jidoka.Examples.PrReviewer.Tools.LoadDiff
    tool Jidoka.Examples.PrReviewer.Tools.DetectReviewFindings
  end

  lifecycle do
    output_guardrail Jidoka.Examples.PrReviewer.Guardrails.BlockStyleOnlyReview
  end
end
