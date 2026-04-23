defmodule Moto.Examples.Workflow.Tools.DoubleValue do
  @moduledoc false

  use Moto.Tool,
    name: "workflow_demo_double_value",
    description: "Doubles a value.",
    schema: Zoi.object(%{value: Zoi.integer()})

  @impl true
  def run(%{value: value}, _context) do
    {:ok, %{value: value * 2}}
  end
end
