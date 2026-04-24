defmodule JidokaConsumer.Support.Tools.EvaluateRefundPolicy do
  @moduledoc false

  use Jidoka.Tool,
    description: "Applies a deterministic refund policy to a support case.",
    schema:
      Zoi.object(%{
        customer: Zoi.map(),
        order: Zoi.map(),
        reason: Zoi.string()
      })

  alias JidokaConsumer.Support.Data

  @impl true
  def run(%{customer: customer, order: order, reason: reason}, _context) do
    {:ok, Data.refund_policy(customer, order, reason)}
  end
end
