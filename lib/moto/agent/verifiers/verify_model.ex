defmodule Moto.Agent.Verifiers.VerifyModel do
  @moduledoc false

  use Spark.Dsl.Verifier

  @impl true
  def verify(dsl_state) do
    model = Spark.Dsl.Verifier.get_option(dsl_state, [:agent], :model, :fast)

    case validate_model(model) do
      :ok ->
        :ok

      {:error, message} ->
        {:error,
         Spark.Error.DslError.exception(
           message: message,
           path: [:agent, :model],
           module: Spark.Dsl.Verifier.get_persisted(dsl_state, :module)
         )}
    end
  end

  defp validate_model(model) do
    Moto.model(model)
    :ok
  rescue
    error in [ArgumentError] ->
      {:error, Exception.message(error)}
  end
end
