defmodule JidokaConsumer.Support.Agents.SupportRouterAgent do
  @moduledoc false

  use Jidoka.Agent

  alias JidokaConsumer.Support.Agents.{
    BillingSpecialistAgent,
    OperationsSpecialistAgent,
    WriterSpecialistAgent
  }

  alias JidokaConsumer.Support.Hooks.CapabilityRouter
  alias JidokaConsumer.Support.Guardrails.SensitiveDataGuardrail
  alias JidokaConsumer.Support.Ticket
  alias JidokaConsumer.Support.Tools.GetSupportTicket
  alias JidokaConsumer.Support.Workflows.{EscalationDraft, ProcessRefundRequest}

  @context_fields %{
    actor: Zoi.map(),
    channel: Zoi.string() |> Zoi.default("support_chat"),
    session: Zoi.string() |> Zoi.optional(),
    account_id: Zoi.string() |> Zoi.optional(),
    customer_id: Zoi.string() |> Zoi.optional(),
    order_id: Zoi.string() |> Zoi.optional()
  }

  agent do
    id :support_router_agent

    description "Consumer support router with tickets, workflows, specialists, handoffs, and guardrails."

    schema Zoi.object(@context_fields)
  end

  defaults do
    model :fast

    instructions """
    You are the front-door support agent for the Jidoka Phoenix consumer demo.
    The application owns the support domain and exposes local ETS-backed Ash support ticket tools.

    Choose the smallest support capability that completes the request:
    - For a complete refund request with account id, order id, and reason, call process_refund_request.
    - For one known ticket id, call get_support_ticket.
    - For current support work, call list_support_tickets.
    - For ticket escalation, assignment, resolution, or status changes, call update_support_ticket.
    - For escalation notes with an account id and issue, call draft_escalation.
    - For ambiguous billing, operations, or writing judgment, delegate to the matching specialist.
    - For ongoing billing ownership, call transfer_billing_ownership.

    Ask for missing customer id, account id, order id, or issue details before creating a ticket or running a workflow.
    Delegate to exactly one specialist or workflow when the fit is clear, then return the result with minimal framing.

    When confirming ticket creation, use this Markdown layout:

    Support ticket created successfully.

    - **Ticket ID:** <ticket id>
    - **Customer:** <customer id>
    - **Order:** <order id or "not provided">
    - **Priority:** <priority>
    - **Status:** <status>
    - **Issue:** <one-sentence issue summary>

    The ticket is now open and ready for assignment.

    When confirming ticket updates, use the same multi-line Markdown style with
    the changed fields as bullets. Do not return dash-separated inline field
    summaries.

    When showing an existing ticket, use this Markdown layout:

    **Ticket Details:**

    - **Ticket ID:** <ticket id>
    - **Customer:** <customer id>
    - **Order:** <order id or "not provided">
    - **Priority:** <priority>
    - **Status:** <status>
    - **Subject:** <subject>
    - **Assignee:** <assignee or "unassigned">
    - **Issue:** <one-sentence issue summary>

    **Why This Needs Follow-Up:**

    <short operational explanation>

    **Recommended Next Owner:**

    <owner recommendation and concrete next action>
    """
  end

  capabilities do
    ash_resource Ticket
    tool(GetSupportTicket)

    workflow(ProcessRefundRequest,
      as: :process_refund_request,
      description:
        "Review a refund request and create the support ticket in one deterministic process.",
      forward_context: {:only, [:actor, :domain, :channel, :session]},
      result: :structured
    )

    workflow(EscalationDraft,
      as: :draft_escalation,
      description: "Classify an escalation and draft an internal support note.",
      forward_context: {:only, [:channel, :session, :account_id]},
      result: :structured
    )

    subagent BillingSpecialistAgent,
      timeout: 30_000,
      forward_context: {:only, [:channel, :session, :account_id, :order_id]},
      result: :structured

    handoff BillingSpecialistAgent,
      as: :transfer_billing_ownership,
      description: "Transfer ongoing billing conversation ownership to the billing specialist.",
      forward_context: {:only, [:channel, :session, :account_id, :order_id]}

    subagent OperationsSpecialistAgent,
      timeout: 30_000,
      forward_context: {:only, [:channel, :session, :account_id, :order_id]},
      result: :structured

    subagent WriterSpecialistAgent,
      timeout: 30_000,
      forward_context: {:only, [:channel, :session, :account_id]},
      result: :text
  end

  lifecycle do
    before_turn(CapabilityRouter)
    input_guardrail SensitiveDataGuardrail
  end
end
