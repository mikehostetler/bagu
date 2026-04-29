defmodule Jidoka.Examples.ApprovalFlow.Agents.ApprovalAgent do
  @moduledoc false

  use Jidoka.Agent

  @context_schema Zoi.object(%{
                    notify_pid: Zoi.any() |> Zoi.optional(),
                    actor: Zoi.string() |> Zoi.default("demo-operator")
                  })

  @output_schema Zoi.object(%{
                   action: Zoi.string(),
                   risk_level: Zoi.enum([:low, :medium, :high]),
                   approval_required: Zoi.boolean(),
                   approval_reason: Zoi.string(),
                   result: Zoi.string()
                 })

  agent do
    id :approval_flow_agent
    schema @context_schema

    output do
      schema @output_schema
      retries(1)
      on_validation_error(:repair)
    end
  end

  defaults do
    model :fast

    instructions """
    You prepare risky operational actions.
    When a user asks you to send a refund, call the send_refund tool.
    The tool guardrail owns approval checks, so do not answer from policy alone.
    """
  end

  capabilities do
    tool Jidoka.Examples.ApprovalFlow.Tools.SendRefund
  end

  lifecycle do
    tool_guardrail Jidoka.Examples.ApprovalFlow.Guardrails.RequireRefundApproval
  end
end
