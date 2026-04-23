defmodule Moto.Examples.Workflow.Workflows.MathPipeline do
  @moduledoc false

  use Moto.Workflow

  alias Moto.Examples.Workflow.Tools.{AddAmount, DoubleValue}

  workflow do
    id :math_pipeline
    description("Adds one to a value and doubles the result.")
    input Zoi.object(%{value: Zoi.integer()})
  end

  steps do
    tool :add, AddAmount,
      input: %{
        value: input(:value),
        amount: value(1)
      }

    tool :double, DoubleValue, input: from(:add)
  end

  output from(:double)
end
