defmodule Moto.Agent.Build do
  @moduledoc false

  @spec before_compile(Macro.Env.t()) :: Macro.t()
  def before_compile(%Macro.Env{} = env) do
    env
    |> Moto.Agent.Definition.build!()
    |> Moto.Agent.Codegen.emit()
  end
end
