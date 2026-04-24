defmodule JidokaConsumer.Support.Workflows.ProcessRefundRequest do
  @moduledoc false

  use Jidoka.Workflow

  alias JidokaConsumer.Support.Fns
  alias JidokaConsumer.Support.Ticket
  alias JidokaConsumer.Support.Tools.{EvaluateRefundPolicy, LoadCustomerProfile, LoadOrder}

  workflow do
    id :process_refund_request
    description "Review a refund request and create the corresponding support ticket."

    input Zoi.object(%{
            account_id: Zoi.string(),
            order_id: Zoi.string(),
            reason: Zoi.string(),
            priority: Zoi.string() |> Zoi.default("high")
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

    function :ticket_input, {Fns, :build_refund_ticket_input, 2},
      input: %{
        decision: from(:decision),
        priority: input(:priority)
      }

    tool :ticket, Ticket.Jido.Create, input: from(:ticket_input)

    function :result, {Fns, :finalize_processed_refund, 2},
      input: %{
        ticket: from(:ticket)
      }
  end

  output from(:result)
end
