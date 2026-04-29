defmodule Jidoka.Examples.ApprovalFlow.Tools.SendRefund do
  @moduledoc false

  use Jidoka.Tool,
    name: "send_refund",
    description: "Sends a fixture-backed refund when the approval flag is present.",
    schema:
      Zoi.object(%{
        customer_id: Zoi.string(),
        amount: Zoi.float(),
        approved: Zoi.boolean() |> Zoi.default(false)
      })

  @impl true
  def run(%{approved: true, customer_id: customer_id, amount: amount}, _context) do
    {:ok, %{refund_id: "rfnd_demo_001", customer_id: customer_id, amount: amount, status: :sent}}
  end

  def run(%{approved: false}, _context), do: {:error, :approval_required}
end
