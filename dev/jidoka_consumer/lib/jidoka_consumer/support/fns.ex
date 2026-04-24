defmodule JidokaConsumer.Support.Fns do
  @moduledoc false

  @spec finalize_refund_decision(map(), map()) :: map()
  def finalize_refund_decision(
        %{account_id: account_id, order_id: order_id, policy: policy, reason: reason},
        _context
      ) do
    %{
      workflow: :refund_review,
      account_id: account_id,
      order_id: order_id,
      reason: reason,
      decision: policy.decision,
      refund_type: policy.refund_type,
      rationale: policy.rationale,
      next_action: policy.next_action,
      ticket_subject: "Refund review for #{order_id}",
      ticket_category: "refund",
      ticket_priority: ticket_priority(policy.decision)
    }
  end

  @spec build_refund_ticket_input(map(), map()) :: map()
  def build_refund_ticket_input(%{decision: decision, priority: priority}, _context) do
    %{
      customer_id: decision.account_id,
      order_id: decision.order_id,
      subject: decision.ticket_subject,
      description: refund_ticket_description(decision),
      status: "open",
      priority: priority || decision.ticket_priority,
      category: decision.ticket_category,
      assignee: "billing_specialist"
    }
  end

  @spec finalize_processed_refund(map(), map()) :: map()
  def finalize_processed_refund(%{ticket: ticket}, _context) do
    %{
      workflow: :process_refund_request,
      ticket_id: ticket.id,
      customer_id: ticket.customer_id,
      order_id: ticket.order_id,
      status: ticket.status,
      priority: ticket.priority,
      assignee: ticket.assignee,
      issue: ticket.subject,
      decision_summary: ticket.description
    }
  end

  @spec build_escalation_prompt(map(), map()) :: map()
  def build_escalation_prompt(
        %{account_id: account_id, classification: classification, issue: issue, channel: channel},
        _context
      ) do
    prompt = """
    Draft an internal support escalation note.
    Account: #{account_id}
    Channel: #{channel}
    Severity: #{classification.severity}
    Queue: #{classification.queue}
    Human review required: #{classification.requires_human}
    SLA minutes: #{classification.sla_minutes}
    Customer issue: #{issue}

    Return 3 short bullet points:
    1. what happened
    2. what support should do next
    3. what to tell the customer
    """

    %{
      prompt: String.trim(prompt),
      queue: classification.queue,
      severity: classification.severity
    }
  end

  @spec finalize_escalation_result(map(), map()) :: map()
  def finalize_escalation_result(%{classification: classification, draft: draft}, _context) do
    %{
      workflow: :escalation_draft,
      severity: classification.severity,
      queue: classification.queue,
      requires_human: classification.requires_human,
      sla_minutes: classification.sla_minutes,
      draft: draft
    }
  end

  defp ticket_priority(:approve), do: "high"
  defp ticket_priority(:manual_review), do: "high"
  defp ticket_priority(_decision), do: "normal"

  defp refund_ticket_description(decision) do
    """
    Refund decision: #{decision.decision}
    Refund type: #{decision.refund_type}
    Reason: #{decision.reason}
    Rationale: #{decision.rationale}
    Next action: #{decision.next_action}
    """
    |> String.trim()
  end
end
