defmodule Moto.Agent.Verifiers.VerifyAshResources do
  @moduledoc false

  use Spark.Dsl.Verifier

  @impl true
  def verify(dsl_state) do
    dsl_state
    |> Spark.Dsl.Verifier.get_entities([:tools])
    |> Enum.filter(&match?(%Moto.Agent.Dsl.AshResource{}, &1))
    |> Enum.reduce_while(:ok, fn ash_resource_ref, :ok ->
      case Moto.Agent.AshResources.validate_resource(ash_resource_ref.resource) do
        :ok ->
          {:cont, :ok}

        {:error, message} ->
          {:halt, {:error, resource_error(dsl_state, ash_resource_ref, message)}}
      end
    end)
  end

  defp resource_error(dsl_state, ash_resource_ref, message) do
    Spark.Error.DslError.exception(
      message: message,
      path: [:tools, :ash_resource],
      module: Spark.Dsl.Verifier.get_persisted(dsl_state, :module),
      location: Spark.Dsl.Entity.anno(ash_resource_ref)
    )
  end
end
