defmodule Jidoka.Examples.PrReviewer.Tools.DetectReviewFindings do
  @moduledoc false

  use Jidoka.Tool,
    description: "Detects deterministic review findings in the fixture diff.",
    schema: Zoi.object(%{diff: Zoi.string()})

  @impl true
  def run(%{diff: diff}, _context) do
    if String.contains?(diff, "Payment.refund") and not String.contains?(diff, "authorize") do
      {:ok,
       %{
         findings: [
           %{
             priority: "P1",
             file: "lib/refunds.ex",
             line: 2,
             title: "Refund execution bypasses approval",
             body: "The new refund path calls Payment.refund without checking approval state."
           }
         ],
         test_gaps: ["Add a test that unapproved refunds are rejected."]
       }}
    else
      {:ok, %{findings: [], test_gaps: []}}
    end
  end
end
