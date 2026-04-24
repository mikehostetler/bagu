defmodule JidokaConsumer.Support.Tools.GetSupportTicket do
  @moduledoc false

  use Jidoka.Tool,
    name: "get_support_ticket",
    description: "Lookup one support ticket by id and return a JSON-safe ticket summary.",
    schema: Zoi.object(%{id: Zoi.string()})

  alias JidokaConsumer.Support
  alias JidokaConsumer.Support.Ticket

  @impl true
  def run(%{id: id}, context) do
    ash_context = %{
      domain: Map.get(context, :domain, Support),
      actor: Map.get(context, :actor)
    }

    case Ticket.Jido.Read.run(%{}, ash_context) do
      {:ok, %{result: tickets}} when is_list(tickets) ->
        {:ok, find_ticket(tickets, id)}

      {:ok, tickets} when is_list(tickets) ->
        {:ok, find_ticket(tickets, id)}

      {:error, reason} ->
        {:ok,
         %{
           found: false,
           ticket_id: id,
           message: "Could not read support tickets: #{Jidoka.format_error(reason)}"
         }}
    end
  end

  defp find_ticket(tickets, id) do
    case Enum.find(tickets, &(&1.id == id)) do
      nil ->
        %{
          found: false,
          ticket_id: id,
          message: "No support ticket matched #{id}."
        }

      ticket ->
        %{
          found: true,
          id: ticket.id,
          customer_id: ticket.customer_id,
          order_id: ticket.order_id,
          subject: ticket.subject,
          description: ticket.description,
          status: ticket.status,
          priority: ticket.priority,
          category: ticket.category,
          assignee: ticket.assignee || "unassigned",
          resolution: ticket.resolution
        }
    end
  end
end
