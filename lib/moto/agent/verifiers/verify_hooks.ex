defmodule Moto.Agent.Verifiers.VerifyHooks do
  @moduledoc false

  use Spark.Dsl.Verifier

  @impl true
  def verify(dsl_state) do
    dsl_state
    |> Spark.Dsl.Verifier.get_entities([:hooks])
    |> Enum.reduce_while(:ok, fn hook_ref, :ok ->
      case Moto.Hooks.validate_dsl_hook_ref(stage_for(hook_ref), hook_ref.hook) do
        :ok ->
          {:cont, :ok}

        {:error, message} ->
          {:halt, {:error, hook_error(dsl_state, hook_ref, message)}}
      end
    end)
  end

  defp stage_for(%Moto.Agent.Dsl.BeforeTurnHook{}), do: :before_turn
  defp stage_for(%Moto.Agent.Dsl.AfterTurnHook{}), do: :after_turn
  defp stage_for(%Moto.Agent.Dsl.InterruptHook{}), do: :on_interrupt

  defp hook_error(dsl_state, hook_ref, message) do
    Spark.Error.DslError.exception(
      message: message,
      path: [:hooks, stage_for(hook_ref)],
      module: Spark.Dsl.Verifier.get_persisted(dsl_state, :module),
      location: Spark.Dsl.Entity.anno(hook_ref)
    )
  end
end
