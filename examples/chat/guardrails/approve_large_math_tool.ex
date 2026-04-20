defmodule Moto.Examples.Chat.Guardrails.ApproveLargeMathTool do
  use Moto.Guardrail, name: "approve_large_math_tool"

  @threshold 100

  @impl true
  def call(%Moto.Guardrails.Tool{tool_name: "add_numbers", arguments: arguments, context: context}) do
    a = Map.get(arguments, :a, Map.get(arguments, "a", 0))
    b = Map.get(arguments, :b, Map.get(arguments, "b", 0))

    if a + b > @threshold do
      notify_pid = Map.get(context, :notify_pid, Map.get(context, "notify_pid"))
      tenant = Map.get(context, :tenant, Map.get(context, "tenant"))

      {:interrupt,
       %{
         kind: :approval,
         message: "Large calculations require approval in the demo.",
         data: %{notify_pid: notify_pid, tenant: tenant, reason: :large_calculation}
       }}
    else
      :ok
    end
  end

  def call(%Moto.Guardrails.Tool{}), do: :ok
end
