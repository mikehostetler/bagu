defmodule Moto.ImportedAgent.Registries do
  @moduledoc false

  @type t :: %{
          tools: Moto.Tool.registry(),
          skills: Moto.Skill.registry(),
          subagents: Moto.Subagent.registry(),
          plugins: Moto.Plugin.registry(),
          hooks: Moto.Hook.registry(),
          guardrails: Moto.Guardrail.registry()
        }

  @spec with_registries(keyword(), (t() -> term())) :: term()
  def with_registries(opts, fun) when is_list(opts) and is_function(fun, 1) do
    with {:ok, registries} <- normalize(opts) do
      fun.(registries)
    end
  end

  @spec normalize(keyword()) :: {:ok, t()} | {:error, String.t()}
  def normalize(opts) when is_list(opts) do
    with {:ok, tool_registry} <- available_tool_registry(opts),
         {:ok, skill_registry} <- available_skill_registry(opts),
         {:ok, subagent_registry} <- available_subagent_registry(opts),
         {:ok, plugin_registry} <- available_plugin_registry(opts),
         {:ok, hook_registry} <- available_hook_registry(opts),
         {:ok, guardrail_registry} <- available_guardrail_registry(opts) do
      {:ok,
       %{
         tools: tool_registry,
         skills: skill_registry,
         subagents: subagent_registry,
         plugins: plugin_registry,
         hooks: hook_registry,
         guardrails: guardrail_registry
       }}
    end
  end

  @spec normalize_opts(keyword()) :: {:ok, keyword()} | {:error, String.t()}
  def normalize_opts(opts) when is_list(opts) do
    with {:ok, registries} <- normalize(opts) do
      {:ok,
       opts
       |> Keyword.put(:available_tools, registries.tools)
       |> Keyword.put(:available_skills, registries.skills)
       |> Keyword.put(:available_subagents, registries.subagents)
       |> Keyword.put(:available_plugins, registries.plugins)
       |> Keyword.put(:available_hooks, registries.hooks)
       |> Keyword.put(:available_guardrails, registries.guardrails)}
    end
  end

  @spec resolve_hooks(Moto.Hooks.stage_map(), Moto.Hook.registry()) ::
          {:ok, Moto.Hooks.stage_map()} | {:error, String.t()}
  def resolve_hooks(hooks, hook_registry) do
    hooks
    |> Enum.reduce_while({:ok, Moto.Hooks.default_stage_map()}, fn {stage, hook_names}, {:ok, acc} ->
      case Moto.Hook.resolve_hook_names(hook_names, hook_registry) do
        {:ok, modules} -> {:cont, {:ok, Map.put(acc, stage, modules)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @spec resolve_guardrails(Moto.Guardrails.stage_map(), Moto.Guardrail.registry()) ::
          {:ok, Moto.Guardrails.stage_map()} | {:error, String.t()}
  def resolve_guardrails(guardrails, guardrail_registry) do
    guardrails
    |> Enum.reduce_while({:ok, Moto.Guardrails.default_stage_map()}, fn {stage, guardrail_names}, {:ok, acc} ->
      case Moto.Guardrail.resolve_guardrail_names(guardrail_names, guardrail_registry) do
        {:ok, modules} -> {:cont, {:ok, Map.put(acc, stage, modules)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @spec resolve_skills([String.t()], Moto.Skill.registry()) ::
          {:ok, [Moto.Skill.ref()]} | {:error, String.t()}
  def resolve_skills(skill_names, skill_registry) do
    Moto.Skill.resolve_skill_refs(skill_names, skill_registry)
  end

  @spec resolve_subagents([map()], Moto.Subagent.registry()) ::
          {:ok, [Moto.Subagent.t()]} | {:error, String.t()}
  def resolve_subagents(subagents, subagent_registry) do
    subagents
    |> Enum.reduce_while({:ok, []}, fn subagent_spec, {:ok, acc} ->
      with {:ok, agent_module} <-
             Moto.Subagent.resolve_subagent_name(subagent_spec.agent, subagent_registry),
           {:ok, subagent} <-
             Moto.Subagent.new(
               agent_module,
               as: Map.get(subagent_spec, :as),
               description: Map.get(subagent_spec, :description),
               target: imported_subagent_target(subagent_spec),
               timeout: Map.get(subagent_spec, :timeout_ms, 30_000),
               forward_context: Map.get(subagent_spec, :forward_context, :public),
               result: Map.get(subagent_spec, :result, :text)
             ) do
        {:cont, {:ok, acc ++ [subagent]}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp available_tool_registry(opts) do
    opts
    |> Keyword.get(:available_tools, [])
    |> Moto.Tool.normalize_available_tools()
  end

  defp available_skill_registry(opts) do
    opts
    |> Keyword.get(:available_skills, [])
    |> Moto.Skill.normalize_available_skills()
  end

  defp available_plugin_registry(opts) do
    opts
    |> Keyword.get(:available_plugins, [])
    |> Moto.Plugin.normalize_available_plugins()
  end

  defp available_subagent_registry(opts) do
    opts
    |> Keyword.get(:available_subagents, [])
    |> Moto.Subagent.normalize_available_subagents()
  end

  defp available_hook_registry(opts) do
    opts
    |> Keyword.get(:available_hooks, [])
    |> Moto.Hook.normalize_available_hooks()
  end

  defp available_guardrail_registry(opts) do
    opts
    |> Keyword.get(:available_guardrails, [])
    |> Moto.Guardrail.normalize_available_guardrails()
  end

  defp imported_subagent_target(%{target: "ephemeral"}), do: :ephemeral
  defp imported_subagent_target(%{target: "peer", peer_id: peer_id}), do: {:peer, peer_id}

  defp imported_subagent_target(%{target: "peer", peer_id_context_key: key}),
    do: {:peer, {:context, key}}
end
