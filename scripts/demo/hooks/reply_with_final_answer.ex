defmodule Moto.Scripts.Demo.Hooks.ReplyWithFinalAnswer do
  use Moto.Hook, name: "reply_with_final_answer"

  @impl true
  def call(%Moto.Hooks.BeforeTurn{} = input) do
    tenant = Map.get(input.context, :tenant, Map.get(input.context, "tenant"))

    tenant_instruction =
      case tenant do
        nil -> ""
        value -> "\nRespect the runtime tenant context: #{value}."
      end

    {:ok,
     %{
       message:
         "#{input.message}\n\nReply with only the final answer.#{tenant_instruction}",
       metadata: %{reply_style: :final_answer_only, tenant: tenant}
     }}
  end
end
