defmodule Moto.Workflow.StepAction do
  @moduledoc false

  use Jido.Action,
    name: "moto_workflow_step",
    description: "Internal Moto workflow step adapter.",
    schema:
      Zoi.object(%{
        __moto_workflow_definition__: Zoi.any(),
        __moto_workflow_step__: Zoi.any(),
        __moto_workflow_state__: Zoi.any() |> Zoi.optional(),
        input: Zoi.any() |> Zoi.optional()
      }),
    output_schema:
      Zoi.object(%{
        __moto_workflow_state__: Zoi.any()
      })

  @impl true
  def run(params, context) do
    Moto.Workflow.Runtime.run_step(params, context)
  end
end
