defmodule Moto.Examples.Workflow.Tools.AddAmount do
  @moduledoc false

  use Moto.Tool,
    name: "workflow_demo_add_amount",
    description: "Adds a fixed amount to a value.",
    schema:
      Zoi.object(%{
        value: Zoi.integer(),
        amount: Zoi.integer() |> Zoi.default(1)
      })

  @impl true
  def run(%{value: value, amount: amount}, _context) do
    {:ok, %{value: value + amount}}
  end
end
