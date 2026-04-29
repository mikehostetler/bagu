defmodule Jidoka.Examples.SupportTriage.Tools.LoadTicket do
  @moduledoc false

  use Jidoka.Tool,
    description: "Loads a support ticket from the example fixture set.",
    schema: Zoi.object(%{ticket_id: Zoi.string()})

  @tickets %{
    "TCK-1001" => %{
      ticket_id: "TCK-1001",
      customer: "Northwind Finance",
      plan: "enterprise",
      subject: "Duplicate invoice charge",
      body: "We were charged twice for invoice INV-4432 and need this fixed before month end.",
      sentiment: "frustrated"
    },
    "TCK-1002" => %{
      ticket_id: "TCK-1002",
      customer: "Bluebird Labs",
      plan: "startup",
      subject: "Webhook retry behavior",
      body: "Our webhook endpoint was down for 20 minutes. Did Jidoka retry the events?",
      sentiment: "neutral"
    }
  }

  @impl true
  def run(%{ticket_id: ticket_id}, _context) do
    case Map.fetch(@tickets, ticket_id) do
      {:ok, ticket} -> {:ok, ticket}
      :error -> {:error, {:unknown_ticket, ticket_id}}
    end
  end
end
