defmodule Jidoka.Examples.DocumentIntake.Tools.LoadDocument do
  @moduledoc false

  use Jidoka.Tool,
    description: "Loads a fixture-backed inbound document.",
    schema: Zoi.object(%{document_id: Zoi.string()})

  @documents %{
    "DOC-INV" => %{document_id: "DOC-INV", text: "Invoice INV-4432 from Atlas Cloud Services for $1475.50."},
    "DOC-LEGAL" => %{document_id: "DOC-LEGAL", text: "Contract note: DPA requires legal review before signature."},
    "DOC-SUPPORT" => %{document_id: "DOC-SUPPORT", text: "Support request: customer cannot access SSO settings."}
  }

  @impl true
  def run(%{document_id: document_id}, _context) do
    case Map.fetch(@documents, document_id) do
      {:ok, document} -> {:ok, document}
      :error -> {:error, {:unknown_document, document_id}}
    end
  end
end
