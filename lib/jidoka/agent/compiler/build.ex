defmodule Jidoka.Agent.Build do
  @moduledoc false

  @spec before_compile(Macro.Env.t()) :: Macro.t()
  def before_compile(%Macro.Env{} = env) do
    env
    |> Jidoka.Agent.Definition.build!()
    |> Jidoka.Agent.Codegen.emit()
  end
end
