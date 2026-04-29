defmodule Jidoka.Examples.DocumentIntake.Tools.RouteDocument do
  @moduledoc false

  use Jidoka.Tool,
    description: "Classifies and routes a fixture-backed inbound document.",
    schema: Zoi.object(%{text: Zoi.string()})

  @impl true
  def run(%{text: text}, _context) do
    text_downcase = String.downcase(text)

    cond do
      String.contains?(text_downcase, "invoice") ->
        {:ok, %{document_type: :invoice, route: :finance_ops, confidence: 0.97}}

      String.contains?(text_downcase, "contract") ->
        {:ok, %{document_type: :contract_note, route: :legal_ops, confidence: 0.92}}

      String.contains?(text_downcase, "support") ->
        {:ok, %{document_type: :support_request, route: :support_ops, confidence: 0.9}}

      true ->
        {:error, :unknown_document_type}
    end
  end
end
