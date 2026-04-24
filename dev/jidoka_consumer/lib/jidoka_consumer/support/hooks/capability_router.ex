defmodule JidokaConsumer.Support.Hooks.CapabilityRouter do
  @moduledoc false

  use Jidoka.Hook, name: "support_capability_router"

  @default_tools [
    "process_refund_request",
    "get_support_ticket",
    "list_support_tickets",
    "billing_specialist",
    "operations_specialist",
    "writer_specialist"
  ]

  @impl true
  def call(%Jidoka.Hooks.BeforeTurn{message: message}) when is_binary(message) do
    {route, tools} = route(message)

    {:ok,
     %{
       allowed_tools: tools,
       metadata: %{support_capability_route: route, allowed_tools: tools}
     }}
  end

  def call(_input), do: {:ok, %{}}

  defp route(message) do
    text = String.downcase(message)

    cond do
      contains_any?(text, ["credit card", "card number", "ssn", "social security"]) ->
        {:guardrail_candidate, @default_tools}

      refund_request?(text) and has_account_and_order?(text) ->
        {:refund_process, ["process_refund_request"]}

      ticket_lookup?(text) ->
        {:ticket_lookup, ["get_support_ticket", "billing_specialist", "operations_specialist"]}

      contains_any?(text, ["list", "queue", "current tickets", "open tickets", "show tickets"]) ->
        {:ticket_queue, ["list_support_tickets"]}

      contains_any?(text, ["ticket", "escalate", "assign", "resolve", "status", "mark it"]) ->
        {:ticket_update,
         ["list_support_tickets", "update_support_ticket", "create_support_ticket"]}

      contains_any?(text, ["draft", "write", "rewrite", "copy"]) and
          contains_any?(text, ["reply", "response", "message", "note"]) ->
        {:writer, ["writer_specialist", "draft_escalation"]}

      contains_any?(text, ["chargeback", "legal", "sla", "executive", "escalation note"]) ->
        {:escalation_workflow, ["draft_escalation", "writer_specialist"]}

      contains_any?(text, ["transfer", "handoff", "ongoing follow-up", "next turn"]) ->
        {:handoff, ["transfer_billing_ownership", "billing_specialist"]}

      contains_any?(text, [
        "billing",
        "invoice",
        "payment",
        "credit",
        "refund window",
        "store credit"
      ]) ->
        {:billing_specialist, ["billing_specialist", "process_refund_request"]}

      contains_any?(text, [
        "delivery",
        "carrier",
        "shipment",
        "order status",
        "late",
        "access",
        "login"
      ]) ->
        {:operations_specialist, ["operations_specialist", "list_support_tickets"]}

      contains_any?(text, ["create", "reported", "issue", "problem"]) ->
        {:ticket_create, ["create_support_ticket", "process_refund_request"]}

      true ->
        {:default, @default_tools}
    end
  end

  defp refund_request?(text) do
    contains_any?(text, ["refund", "return", "damaged", "broken", "duplicate charge"])
  end

  defp has_account_and_order?(text) do
    String.contains?(text, "acct_") and String.contains?(text, "ord_")
  end

  defp ticket_lookup?(text) do
    String.contains?(text, "ticket ") and
      contains_any?(text, ["show me", "look up", "lookup", "explain", "recommend"])
  end

  defp contains_any?(text, needles) do
    Enum.any?(needles, &String.contains?(text, &1))
  end
end
