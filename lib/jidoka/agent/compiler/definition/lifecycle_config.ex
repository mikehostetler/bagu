defmodule Jidoka.Agent.Definition.LifecycleConfig do
  @moduledoc false

  @spec resolve_hooks!([struct()], module()) :: map()
  def resolve_hooks!(hook_entities, owner_module) when is_list(hook_entities) do
    hook_entities
    |> hooks_stage_map()
    |> normalize_hooks!(owner_module)
  end

  @spec resolve_guardrails!([struct()], module()) :: map()
  def resolve_guardrails!(guardrail_entities, owner_module) when is_list(guardrail_entities) do
    guardrail_entities
    |> guardrails_stage_map()
    |> normalize_guardrails!(owner_module)
  end

  defp normalize_hooks!(hooks, owner_module) do
    with :ok <- ensure_unique_stage_refs!(owner_module, hooks, "hook", [:lifecycle]),
         {:ok, normalized} <- Jidoka.Hooks.normalize_dsl_hooks(hooks) do
      normalized
    else
      {:error, message} ->
        raise Jidoka.Agent.Dsl.Error.exception(
                message: message,
                path: [:lifecycle],
                hint: "Declare hooks as `before_turn`, `after_turn`, or `on_interrupt` inside `lifecycle`.",
                module: owner_module
              )
    end
  end

  defp normalize_guardrails!(guardrails, owner_module) do
    with :ok <- ensure_unique_stage_refs!(owner_module, guardrails, "guardrail", [:lifecycle]),
         {:ok, normalized} <- Jidoka.Guardrails.normalize_dsl_guardrails(guardrails) do
      normalized
    else
      {:error, message} ->
        raise Jidoka.Agent.Dsl.Error.exception(
                message: message,
                path: [:lifecycle],
                hint:
                  "Declare guardrails as `input_guardrail`, `output_guardrail`, or `tool_guardrail` inside `lifecycle`.",
                module: owner_module
              )
    end
  end

  defp ensure_unique_stage_refs!(owner_module, stage_map, label, path) when is_map(stage_map) do
    stage_map
    |> Enum.find_value(fn {stage, refs} ->
      duplicate =
        refs
        |> Enum.frequencies()
        |> Enum.find(fn {_ref, count} -> count > 1 end)

      case duplicate do
        nil -> nil
        {ref, _count} -> {stage, ref}
      end
    end)
    |> case do
      nil ->
        :ok

      {stage, ref} ->
        raise Jidoka.Agent.Dsl.Error.exception(
                message: "#{label} #{inspect(ref)} is defined more than once for #{stage}",
                path: path ++ [stage],
                value: ref,
                hint: "Remove the duplicate #{label} declaration from the #{stage} lifecycle stage.",
                module: owner_module
              )
    end
  end

  defp hooks_stage_map(hook_entities) do
    Enum.reduce(hook_entities, Jidoka.Hooks.default_stage_map(), fn
      %Jidoka.Agent.Dsl.BeforeTurnHook{hook: hook}, acc ->
        Map.update!(acc, :before_turn, &(&1 ++ [hook]))

      %Jidoka.Agent.Dsl.AfterTurnHook{hook: hook}, acc ->
        Map.update!(acc, :after_turn, &(&1 ++ [hook]))

      %Jidoka.Agent.Dsl.InterruptHook{hook: hook}, acc ->
        Map.update!(acc, :on_interrupt, &(&1 ++ [hook]))
    end)
  end

  defp guardrails_stage_map(guardrail_entities) do
    Enum.reduce(guardrail_entities, Jidoka.Guardrails.default_stage_map(), fn
      %Jidoka.Agent.Dsl.InputGuardrail{guardrail: guardrail}, acc ->
        Map.update!(acc, :input, &(&1 ++ [guardrail]))

      %Jidoka.Agent.Dsl.OutputGuardrail{guardrail: guardrail}, acc ->
        Map.update!(acc, :output, &(&1 ++ [guardrail]))

      %Jidoka.Agent.Dsl.ToolGuardrail{guardrail: guardrail}, acc ->
        Map.update!(acc, :tool, &(&1 ++ [guardrail]))
    end)
  end
end
