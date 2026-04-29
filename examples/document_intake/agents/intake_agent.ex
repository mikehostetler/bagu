defmodule Jidoka.Examples.DocumentIntake.Agents.IntakeAgent do
  @moduledoc false

  use Jidoka.Agent

  @output_schema Zoi.object(%{
                   document_type: Zoi.enum([:invoice, :contract_note, :support_request]),
                   route: Zoi.enum([:finance_ops, :legal_ops, :support_ops]),
                   confidence: Zoi.float(),
                   summary: Zoi.string(),
                   extracted_fields:
                     Zoi.object(%{
                       invoice_number: Zoi.string() |> Zoi.optional(),
                       vendor: Zoi.string() |> Zoi.optional(),
                       amount: Zoi.float() |> Zoi.optional(),
                       contract_topic: Zoi.string() |> Zoi.optional(),
                       issue: Zoi.string() |> Zoi.optional()
                     })
                 })

  agent do
    id :document_intake_agent

    output do
      schema @output_schema
      retries(1)
      on_validation_error(:repair)
    end
  end

  defaults do
    model :fast

    instructions """
    You classify operational documents and route them to the right queue.
    Extract only the normalized fields needed by downstream teams.
    """
  end

  capabilities do
    tool Jidoka.Examples.DocumentIntake.Tools.LoadDocument
    tool Jidoka.Examples.DocumentIntake.Tools.RouteDocument
  end
end
