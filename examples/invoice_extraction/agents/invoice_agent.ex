defmodule Jidoka.Examples.InvoiceExtraction.Agents.InvoiceAgent do
  @moduledoc false

  use Jidoka.Agent

  @output_schema Zoi.object(%{
                   vendor: Zoi.string(),
                   invoice_number: Zoi.string(),
                   issued_on: Zoi.string(),
                   due_on: Zoi.string(),
                   line_items: Zoi.list(Zoi.any()),
                   total: Zoi.float(),
                   warnings: Zoi.list(Zoi.string())
                 })

  agent do
    id :invoice_extraction_agent

    output do
      schema @output_schema
      retries(1)
      on_validation_error(:repair)
    end
  end

  defaults do
    model :fast

    instructions """
    You extract invoice fields from raw invoice text.
    Return vendor, invoice number, dates, line items, totals, and validation warnings.
    """
  end

  capabilities do
    tool Jidoka.Examples.InvoiceExtraction.Tools.LoadInvoice
    tool Jidoka.Examples.InvoiceExtraction.Tools.ParseInvoice
  end
end
