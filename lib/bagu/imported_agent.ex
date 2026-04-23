defmodule Bagu.ImportedAgent do
  @moduledoc """
  Runtime representation of a constrained JSON/YAML-authored Bagu agent.

  Most applications should call `Bagu.import_agent/2` or
  `Bagu.import_agent_file/2` rather than this module directly. The struct is
  still documented because public Bagu APIs return it.
  """

  alias Bagu.ImportedAgent.{Codec, Registries, Spec}

  @enforce_keys [
    :spec,
    :runtime_module,
    :tool_modules,
    :skill_refs,
    :mcp_tools,
    :subagents,
    :workflows,
    :plugin_modules,
    :hook_modules,
    :guardrail_modules
  ]
  defstruct [
    :spec,
    :runtime_module,
    :tool_modules,
    :skill_refs,
    :mcp_tools,
    :subagents,
    :workflows,
    :plugin_modules,
    :hook_modules,
    :guardrail_modules
  ]

  @type t :: %__MODULE__{
          spec: struct(),
          runtime_module: module(),
          tool_modules: [module()],
          skill_refs: [term()],
          mcp_tools: [map()],
          subagents: [Bagu.Subagent.t()],
          workflows: [Bagu.Workflow.Capability.t()],
          plugin_modules: [module()],
          hook_modules: map(),
          guardrail_modules: map()
        }

  @spec import(map() | binary() | struct(), keyword()) :: {:ok, t()} | {:error, term()}
  def import(source, opts \\ [])

  def import(%Spec{} = spec, opts) do
    Registries.with_registries(opts, fn registries ->
      build_from_source(spec, registries)
    end)
  end

  def import(source, opts) when is_map(source) do
    Registries.with_registries(opts, fn registries ->
      build_from_source(source, registries)
    end)
  end

  def import(source, opts) when is_binary(source) do
    with {:ok, attrs} <- Codec.decode(source, Keyword.get(opts, :format, :auto)) do
      Registries.with_registries(opts, fn registries ->
        build_from_source(attrs, registries)
      end)
    end
  end

  def import(other, _opts),
    do: {:error, "cannot import Bagu agent from #{inspect(other)}"}

  @spec import_file(Path.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def import_file(path, opts \\ []) when is_binary(path) do
    with {:ok, contents} <- File.read(path),
         {:ok, format} <- Codec.detect_file_format(path, Keyword.get(opts, :format)),
         {:ok, attrs} <- Codec.decode(contents, format),
         expanded_attrs <- Codec.expand_skill_paths(attrs, Path.dirname(path)),
         {:ok, agent} <- __MODULE__.import(expanded_attrs, opts) do
      {:ok, agent}
    else
      {:error, :enoent} ->
        {:error, "could not read agent spec file: #{path}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec start_link(t(), keyword()) :: DynamicSupervisor.on_start_child()
  def start_link(%__MODULE__{runtime_module: runtime_module}, opts \\ []) do
    Bagu.Runtime.start_agent(runtime_module, opts)
  end

  @spec definition(t()) :: map()
  def definition(%__MODULE__{} = agent) do
    definition_map(
      agent.spec,
      agent.runtime_module,
      agent.tool_modules,
      agent.skill_refs,
      agent.mcp_tools,
      agent.subagents,
      agent.workflows,
      agent.plugin_modules,
      agent.hook_modules,
      agent.guardrail_modules,
      request_transformer(agent.spec, agent.runtime_module)
    )
  end

  @spec encode(t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def encode(%__MODULE__{spec: spec}, opts \\ []), do: Codec.encode(spec, opts)

  @doc """
  Formats an imported-agent error for human-readable messages.
  """
  @spec format_error(term()) :: String.t()
  def format_error(reason), do: Codec.format_error(reason)

  defp build(
         %Spec{} = spec,
         tool_registry,
         skill_registry,
         subagent_registry,
         workflow_registry,
         plugin_registry,
         hook_registry,
         guardrail_registry
       ) do
    with {:ok, direct_tool_modules} <- Bagu.Tool.resolve_tool_names(spec.tools, tool_registry),
         {:ok, skill_refs} <- Registries.resolve_skills(spec.skills, skill_registry),
         {:ok, resolved_subagents} <-
           Registries.resolve_subagents(spec.subagents, subagent_registry),
         {:ok, resolved_workflows} <-
           Registries.resolve_workflows(spec.workflows, workflow_registry),
         {:ok, plugin_modules} <- Bagu.Plugin.resolve_plugin_names(spec.plugins, plugin_registry),
         {:ok, plugin_tool_modules} <- Bagu.Plugin.plugin_actions(plugin_modules),
         skill_tool_modules =
           Bagu.Skill.action_modules(%{refs: skill_refs, load_paths: spec.skill_paths}),
         {:ok, direct_tool_names} <-
           Bagu.Tool.action_names(direct_tool_modules ++ skill_tool_modules ++ plugin_tool_modules),
         subagent_tool_modules <-
           resolved_subagents
           |> Enum.with_index()
           |> Enum.map(fn {subagent, index} ->
             Bagu.Subagent.tool_module(generated_module_base(spec), subagent, index)
           end),
         workflow_tool_modules <-
           resolved_workflows
           |> Enum.with_index()
           |> Enum.map(fn {workflow, index} ->
             Bagu.Workflow.Capability.tool_module(generated_module_base(spec), workflow, index)
           end),
         {:ok, hook_modules} <- Registries.resolve_hooks(spec.hooks, hook_registry),
         {:ok, guardrail_modules} <-
           Registries.resolve_guardrails(spec.guardrails, guardrail_registry),
         tool_modules =
           direct_tool_modules ++
             skill_tool_modules ++ plugin_tool_modules ++ subagent_tool_modules ++ workflow_tool_modules,
         :ok <-
           ensure_unique_tool_names(
             direct_tool_names ++ Enum.map(resolved_subagents, & &1.name) ++ Enum.map(resolved_workflows, & &1.name)
           ),
         {:ok, runtime_module} <-
           ensure_runtime_module(
             spec,
             tool_modules,
             skill_refs,
             spec.mcp_tools,
             resolved_subagents,
             resolved_workflows,
             plugin_modules,
             hook_modules,
             guardrail_modules
           ) do
      {:ok,
       %__MODULE__{
         spec: spec,
         runtime_module: runtime_module,
         tool_modules: tool_modules,
         skill_refs: skill_refs,
         mcp_tools: spec.mcp_tools,
         subagents: resolved_subagents,
         workflows: resolved_workflows,
         plugin_modules: plugin_modules,
         hook_modules: hook_modules,
         guardrail_modules: guardrail_modules
       }}
    end
  end

  defp ensure_unique_tool_names(tool_names) do
    if Enum.uniq(tool_names) == tool_names do
      :ok
    else
      duplicates =
        tool_names
        |> Enum.frequencies()
        |> Enum.filter(fn {_name, count} -> count > 1 end)
        |> Enum.map(&elem(&1, 0))
        |> Enum.sort()

      {:error, "duplicate tool names in imported Bagu agent: #{Enum.join(duplicates, ", ")}"}
    end
  end

  defp ensure_runtime_module(
         %Spec{} = spec,
         tool_modules,
         skill_refs,
         mcp_tools,
         subagents,
         workflows,
         plugin_modules,
         hook_modules,
         guardrail_modules
       ) do
    runtime_plugins = runtime_plugins(plugin_modules, spec.memory)

    runtime_module =
      generated_module(
        spec,
        tool_modules,
        skill_refs,
        mcp_tools,
        subagents,
        workflows,
        runtime_plugins,
        hook_modules,
        guardrail_modules
      )

    if Code.ensure_loaded?(runtime_module) do
      {:ok, runtime_module}
    else
      create_runtime_module(
        runtime_module,
        spec,
        tool_modules,
        skill_refs,
        mcp_tools,
        subagents,
        workflows,
        plugin_modules,
        runtime_plugins,
        hook_modules,
        guardrail_modules
      )
    end
  end

  defp generated_module(
         %Spec{} = spec,
         tool_modules,
         skill_refs,
         mcp_tools,
         subagents,
         workflows,
         runtime_plugins,
         hook_modules,
         guardrail_modules
       ) do
    suffix =
      %{
        spec: Spec.to_external_map(spec),
        tools: Enum.map(tool_modules, &inspect/1),
        skills:
          Enum.map(skill_refs, fn
            module when is_atom(module) -> inspect(module)
            name when is_binary(name) -> name
          end),
        mcp_tools: mcp_tools,
        subagents:
          Enum.map(subagents, fn subagent ->
            %{
              name: subagent.name,
              agent: inspect(subagent.agent),
              target: externalize_subagent_target(subagent.target)
            }
          end),
        workflows:
          Enum.map(workflows, fn workflow ->
            %{
              name: workflow.name,
              workflow: inspect(workflow.workflow)
            }
          end),
        plugins: Enum.map(runtime_plugins, &inspect/1),
        hooks:
          Enum.into(hook_modules, %{}, fn {stage, modules} ->
            {stage, Enum.map(modules, &inspect/1)}
          end),
        guardrails:
          Enum.into(guardrail_modules, %{}, fn {stage, modules} ->
            {stage, Enum.map(modules, &inspect/1)}
          end)
      }
      |> Jason.encode!()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)
      |> String.slice(0, 16)
      |> String.upcase()

    Module.concat([__MODULE__, Generated, "Runtime#{suffix}"])
  end

  defp create_runtime_module(
         runtime_module,
         %Spec{} = spec,
         tool_modules,
         skill_refs,
         mcp_tools,
         subagents,
         workflows,
         plugin_modules,
         runtime_plugins,
         hook_modules,
         guardrail_modules
       ) do
    request_transformer_module = Module.concat(runtime_module, RequestTransformer)
    skill_config = %{refs: skill_refs, load_paths: spec.skill_paths}

    effective_request_transformer =
      if Bagu.Memory.requires_request_transformer?(spec.memory) or
           Bagu.Skill.requires_request_transformer?(skill_config) do
        request_transformer_module
      else
        nil
      end

    subagent_tool_modules =
      subagents
      |> Enum.with_index()
      |> Enum.map(fn {subagent, index} ->
        tool_module = Bagu.Subagent.tool_module(generated_module_base(spec), subagent, index)
        Bagu.Subagent.tool_module_ast(tool_module, subagent)
      end)

    workflow_tool_modules =
      workflows
      |> Enum.with_index()
      |> Enum.map(fn {workflow, index} ->
        tool_module = Bagu.Workflow.Capability.tool_module(generated_module_base(spec), workflow, index)
        Bagu.Workflow.Capability.tool_module_ast(tool_module, workflow)
      end)

    generated_tool_modules = subagent_tool_modules ++ workflow_tool_modules

    quoted =
      quote location: :keep do
        if unquote(Macro.escape(effective_request_transformer)) do
          defmodule unquote(request_transformer_module) do
            @moduledoc false
            @behaviour Jido.AI.Reasoning.ReAct.RequestTransformer

            @system_prompt_spec unquote(Macro.escape(spec.instructions))
            @skills_config unquote(Macro.escape(skill_config))

            @impl true
            def transform_request(request, state, config, runtime_context) do
              Bagu.Agent.RequestTransformer.transform_request(
                @system_prompt_spec,
                @skills_config,
                request,
                state,
                config,
                runtime_context
              )
            end
          end
        end

        unquote_splicing(generated_tool_modules)

        use Jido.AI.Agent,
          name: unquote(spec.id),
          system_prompt: unquote(spec.instructions),
          model: unquote(Macro.escape(spec.model)),
          tools: unquote(Macro.escape(tool_modules)),
          plugins: unquote(Macro.escape(runtime_plugins)),
          default_plugins: unquote(Macro.escape(Bagu.Memory.default_plugins(spec.memory))),
          request_transformer: unquote(Macro.escape(effective_request_transformer))

        unquote(
          Bagu.Agent.Runtime.hook_runtime_ast(
            hook_modules,
            spec.context,
            guardrail_modules,
            spec.memory,
            skill_config,
            mcp_tools
          )
        )

        @doc false
        @spec __bagu_owner_module__() :: nil
        def __bagu_owner_module__, do: nil

        @doc false
        @spec __bagu_definition__() :: map()

        def __bagu_definition__ do
          unquote(
            Macro.escape(
              definition_map(
                spec,
                runtime_module,
                tool_modules,
                skill_refs,
                mcp_tools,
                subagents,
                workflows,
                plugin_modules,
                hook_modules,
                guardrail_modules,
                effective_request_transformer
              )
            )
          )
        end
      end

    {:module, ^runtime_module, _binary, _term} =
      Module.create(runtime_module, quoted, Macro.Env.location(__ENV__))

    {:ok, runtime_module}
  rescue
    error in [ArgumentError] ->
      if Code.ensure_loaded?(runtime_module) do
        {:ok, runtime_module}
      else
        {:error, error}
      end
  end

  defp generated_module_base(%Spec{} = spec) do
    suffix =
      spec
      |> Spec.fingerprint()
      |> String.slice(0, 12)
      |> String.upcase()

    Module.concat([__MODULE__, Generated, "Runtime#{suffix}"])
  end

  defp externalize_subagent_target(:ephemeral), do: %{"target" => "ephemeral"}

  defp externalize_subagent_target({:peer, peer_id}) when is_binary(peer_id) do
    %{"target" => "peer", "peer_id" => peer_id}
  end

  defp externalize_subagent_target({:peer, {:context, key}}) do
    %{"target" => "peer", "peer_id_context_key" => to_string(key)}
  end

  defp runtime_plugins(plugin_modules, _memory_config), do: [Bagu.Plugins.RuntimeCompat | plugin_modules]

  defp request_transformer(%Spec{} = spec, runtime_module) do
    if Bagu.Memory.requires_request_transformer?(spec.memory) or
         Bagu.Skill.requires_request_transformer?(%{
           refs: spec.skills,
           load_paths: spec.skill_paths
         }) do
      Module.concat(runtime_module, RequestTransformer)
    else
      nil
    end
  end

  defp definition_map(
         %Spec{} = spec,
         runtime_module,
         tool_modules,
         skill_refs,
         mcp_tools,
         subagents,
         workflows,
         plugin_modules,
         hook_modules,
         guardrail_modules,
         request_transformer
       ) do
    {:ok, plugin_names} = Bagu.Plugin.plugin_names(plugin_modules)

    %{
      kind: :imported_agent_definition,
      module: nil,
      runtime_module: runtime_module,
      id: spec.id,
      name: spec.id,
      description: spec.description,
      instructions: spec.instructions,
      request_transformer: request_transformer,
      configured_model: spec.model,
      model: Bagu.model(spec.model),
      context_schema: nil,
      context: spec.context,
      memory: spec.memory,
      skills: %{refs: skill_refs, load_paths: spec.skill_paths},
      tools: tool_modules,
      tool_names: definition_tool_names(tool_modules, subagents, workflows),
      mcp_tools: mcp_tools,
      subagents: subagents,
      subagent_names: Enum.map(subagents, & &1.name),
      workflows: workflows,
      workflow_names: Enum.map(workflows, & &1.name),
      plugins: plugin_modules,
      plugin_names: plugin_names,
      hooks: hook_modules,
      guardrails: guardrail_modules,
      ash_resources: [],
      ash_domain: nil,
      requires_actor?: false
    }
  end

  defp definition_tool_names(tool_modules, subagents, workflows) do
    loaded_names =
      tool_modules
      |> Enum.reduce([], fn module, acc ->
        if Code.ensure_loaded?(module) and function_exported?(module, :name, 0) do
          [module.name() | acc]
        else
          acc
        end
      end)

    (Enum.reverse(loaded_names) ++ Enum.map(subagents, & &1.name) ++ Enum.map(workflows, & &1.name))
    |> Enum.uniq()
  end

  defp build_from_source(source, %{
         tools: tool_registry,
         skills: skill_registry,
         subagents: subagent_registry,
         workflows: workflow_registry,
         plugins: plugin_registry,
         hooks: hook_registry,
         guardrails: guardrail_registry
       }) do
    with {:ok, spec} <-
           Spec.new(source,
             available_tools: tool_registry,
             available_skills: skill_registry,
             available_subagents: subagent_registry,
             available_workflows: workflow_registry,
             available_plugins: plugin_registry,
             available_hooks: hook_registry,
             available_guardrails: guardrail_registry
           ) do
      build(
        spec,
        tool_registry,
        skill_registry,
        subagent_registry,
        workflow_registry,
        plugin_registry,
        hook_registry,
        guardrail_registry
      )
    end
  end
end
