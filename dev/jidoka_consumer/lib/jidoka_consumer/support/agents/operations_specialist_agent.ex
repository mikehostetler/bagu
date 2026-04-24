defmodule JidokaConsumer.Support.Agents.OperationsSpecialistAgent do
  @moduledoc false

  use Jidoka.Agent

  alias JidokaConsumer.Support.Tools.LoadOrder

  @context_fields %{
    channel: Zoi.string() |> Zoi.default("support_chat"),
    session: Zoi.string() |> Zoi.optional(),
    account_id: Zoi.string() |> Zoi.optional(),
    order_id: Zoi.string() |> Zoi.optional()
  }

  agent do
    id :operations_specialist
    description "Specialist for delivery, account access, and order operations."
    schema Zoi.object(@context_fields)
  end

  defaults do
    model :fast

    instructions """
    You are an operations support specialist.
    Handle delivery delays, account access, fulfillment, and general troubleshooting.
    Return concise next steps with a clear operational status.
    Do not mention delegation or orchestration.
    """
  end

  capabilities do
    tool(LoadOrder)
  end
end
