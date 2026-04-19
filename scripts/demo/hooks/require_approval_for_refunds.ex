defmodule Moto.Scripts.Demo.Hooks.RequireApprovalForRefunds do
  use Moto.Hook, name: "require_approval_for_refunds"

  @impl true
  def call(%Moto.Hooks.AfterTurn{} = input) do
    if refund_request?(input.message) do
      {:interrupt,
       %{
         kind: :approval,
         message: "Refund requests require approval in the demo.",
         data: %{
           notify_pid: Map.get(input.tool_context, :notify_pid),
           reason: :refund_request
         }
       }}
    else
      {:ok, input.outcome}
    end
  end

  defp refund_request?(message) when is_binary(message) do
    message
    |> String.downcase()
    |> String.contains?("refund")
  end
end
