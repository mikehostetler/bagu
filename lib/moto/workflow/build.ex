defmodule Moto.Workflow.Build do
  @moduledoc false

  @spec before_compile(Macro.Env.t()) :: Macro.t()
  def before_compile(%Macro.Env{} = env) do
    env
    |> Moto.Workflow.Definition.build!()
    |> Moto.Workflow.Codegen.emit()
  end
end
