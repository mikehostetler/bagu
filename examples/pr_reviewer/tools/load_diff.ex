defmodule Jidoka.Examples.PrReviewer.Tools.LoadDiff do
  @moduledoc false

  use Jidoka.Tool,
    description: "Loads a fixture-backed pull request diff.",
    schema: Zoi.object(%{pr_id: Zoi.string()})

  @diffs %{
    "PR-17" => """
    diff --git a/lib/refunds.ex b/lib/refunds.ex
    + def issue_refund(order, amount) do
    +   Payment.refund(order.payment_id, amount)
    +   {:ok, :refunded}
    + end
    """
  }

  @impl true
  def run(%{pr_id: pr_id}, _context) do
    case Map.fetch(@diffs, pr_id) do
      {:ok, diff} -> {:ok, %{pr_id: pr_id, diff: diff}}
      :error -> {:error, {:unknown_pr, pr_id}}
    end
  end
end
