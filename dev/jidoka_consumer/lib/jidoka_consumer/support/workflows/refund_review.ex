defmodule JidokaConsumer.Support.Workflows.RefundReview do
  @moduledoc false

  use Jidoka.Workflow

  alias JidokaConsumer.Support.Fns
  alias JidokaConsumer.Support.Tools.{EvaluateRefundPolicy, LoadCustomerProfile, LoadOrder}

  workflow do
    id :refund_review
    description "Deterministic refund review workflow built from support actions."

    input Zoi.object(%{
            account_id: Zoi.string(),
            order_id: Zoi.string(),
            reason: Zoi.string()
          })
  end

  steps do
    tool :customer, LoadCustomerProfile, input: %{account_id: input(:account_id)}

    tool :order, LoadOrder,
      input: %{
        account_id: input(:account_id),
        order_id: input(:order_id)
      }

    tool :policy, EvaluateRefundPolicy,
      input: %{
        customer: from(:customer),
        order: from(:order),
        reason: input(:reason)
      }

    function :decision, {Fns, :finalize_refund_decision, 2},
      input: %{
        account_id: input(:account_id),
        order_id: input(:order_id),
        policy: from(:policy),
        reason: input(:reason)
      }
  end

  output from(:decision)
end
