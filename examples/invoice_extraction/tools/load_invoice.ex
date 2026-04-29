defmodule Jidoka.Examples.InvoiceExtraction.Tools.LoadInvoice do
  @moduledoc false

  use Jidoka.Tool,
    description: "Loads fixture-backed invoice text.",
    schema: Zoi.object(%{invoice_id: Zoi.string()})

  @invoices %{
    "INV-4432" => """
    Vendor: Atlas Cloud Services
    Invoice: INV-4432
    Issued: 2026-04-01
    Due: 2026-04-30
    Line: Platform subscription | 1 | 1200.00
    Line: Usage overage | 1 | 275.50
    Total: 1475.50
    """
  }

  @impl true
  def run(%{invoice_id: invoice_id}, _context) do
    case Map.fetch(@invoices, invoice_id) do
      {:ok, text} -> {:ok, %{invoice_id: invoice_id, text: text}}
      :error -> {:error, {:unknown_invoice, invoice_id}}
    end
  end
end
