defmodule Jidoka.Examples.ApprovalFlow.Guardrails.RequireRefundApproval do
  @moduledoc false

  use Jidoka.Guardrail, name: "require_refund_approval"

  @impl true
  def call(%Jidoka.Guardrails.Tool{tool_name: "send_refund", arguments: arguments, context: context}) do
    amount = Map.get(arguments, :amount, Map.get(arguments, "amount", 0.0))

    if amount >= 500.0 do
      notify_pid = Map.get(context, :notify_pid, Map.get(context, "notify_pid"))

      {:interrupt,
       %{
         kind: :approval,
         message: "Refunds of $500 or more require approval.",
         data: %{notify_pid: notify_pid, amount: amount, reason: :large_refund}
       }}
    else
      :ok
    end
  end

  def call(%Jidoka.Guardrails.Tool{}), do: :ok
end
