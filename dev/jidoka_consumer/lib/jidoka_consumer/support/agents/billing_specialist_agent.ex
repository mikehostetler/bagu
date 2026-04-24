defmodule JidokaConsumer.Support.Agents.BillingSpecialistAgent do
  @moduledoc false

  use Jidoka.Agent

  alias JidokaConsumer.Support.Workflows.RefundReview

  @context_fields %{
    channel: Zoi.string() |> Zoi.default("support_chat"),
    session: Zoi.string() |> Zoi.optional(),
    account_id: Zoi.string() |> Zoi.optional(),
    order_id: Zoi.string() |> Zoi.optional()
  }

  agent do
    id :billing_specialist
    description "Specialist for refunds, credits, and invoice issues."
    schema Zoi.object(@context_fields)
  end

  defaults do
    model :fast

    instructions """
    You are a billing support specialist.
    Focus on refunds, credits, invoice questions, and payment disputes.
    Return concise customer-support guidance with one clear recommendation.
    Do not mention delegation or orchestration.
    """
  end

  capabilities do
    workflow RefundReview,
      as: :review_refund,
      description: "Review refund eligibility when account, order, and reason are available.",
      forward_context: {:only, [:channel, :session]},
      result: :structured
  end
end
