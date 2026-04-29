defmodule Jidoka.Examples.InvoiceExtraction.Tools.ParseInvoice do
  @moduledoc false

  use Jidoka.Tool,
    description: "Parses the known invoice fixture into normalized fields.",
    schema: Zoi.object(%{text: Zoi.string()})

  @impl true
  def run(%{text: text}, _context) do
    if String.contains?(text, "INV-4432") do
      {:ok,
       %{
         vendor: "Atlas Cloud Services",
         invoice_number: "INV-4432",
         issued_on: "2026-04-01",
         due_on: "2026-04-30",
         line_items: [
           %{description: "Platform subscription", quantity: 1, amount: 1200.0},
           %{description: "Usage overage", quantity: 1, amount: 275.5}
         ],
         total: 1475.5,
         warnings: []
       }}
    else
      {:error, :unsupported_invoice_fixture}
    end
  end
end
