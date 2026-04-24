defmodule JidokaConsumer.Support.Tools.ClassifyEscalation do
  @moduledoc false

  use Jidoka.Tool,
    description: "Classifies a support issue into a deterministic escalation queue.",
    schema:
      Zoi.object(%{
        customer: Zoi.map(),
        issue: Zoi.string()
      })

  alias JidokaConsumer.Support.Data

  @impl true
  def run(%{customer: customer, issue: issue}, _context) do
    {:ok, Data.escalation_classification(customer, issue)}
  end
end
