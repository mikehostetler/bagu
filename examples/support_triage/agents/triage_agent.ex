defmodule Jidoka.Examples.SupportTriage.Agents.TriageAgent do
  @moduledoc false

  use Jidoka.Agent

  @context_schema Zoi.object(%{
                    tenant: Zoi.string() |> Zoi.default("acme"),
                    channel: Zoi.string() |> Zoi.default("support")
                  })

  @output_schema Zoi.object(%{
                   category: Zoi.enum([:billing, :technical, :account]),
                   priority: Zoi.enum([:low, :normal, :high, :urgent]),
                   route: Zoi.enum([:billing_ops, :technical_support, :account_success]),
                   needs_human: Zoi.boolean(),
                   summary: Zoi.string(),
                   next_action: Zoi.string()
                 })

  agent do
    id :support_triage_agent
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
    You triage inbound support tickets.
    Use the ticket and routing tools when ticket ids are available.
    Return the final triage decision as structured output.
    """
  end

  capabilities do
    tool Jidoka.Examples.SupportTriage.Tools.LoadTicket
    tool Jidoka.Examples.SupportTriage.Tools.RouteTicket
  end

  lifecycle do
    input_guardrail Jidoka.Examples.SupportTriage.Guardrails.BlockPaymentSecrets
  end
end
