defmodule Moto.Agent.Definition do
  @moduledoc false

  @type t :: map()

  @spec build!(Macro.Env.t()) :: t()
  def build!(%Macro.Env{} = env) do
    owner_module = env.module

    default_name =
      owner_module
      |> Module.split()
      |> List.last()
      |> Macro.underscore()

    name = Spark.Dsl.Extension.get_opt(owner_module, [:agent], :name, default_name)
    configured_model = Spark.Dsl.Extension.get_opt(owner_module, [:agent], :model, :fast)
    resolved_model = resolve_model!(owner_module, configured_model)
    configured_system_prompt = Spark.Dsl.Extension.get_opt(owner_module, [:agent], :system_prompt)

    if is_nil(configured_system_prompt) do
      raise CompileError,
        file: env.file,
        line: env.line,
        description: "Moto.Agent requires `system_prompt` inside `agent do ... end`."
    end

    {runtime_system_prompt, dynamic_system_prompt} =
      case resolve_system_prompt!(owner_module, configured_system_prompt) do
        {:static, prompt} ->
          {prompt, nil}

        {:dynamic, spec} ->
          {nil, spec}
      end

    tool_entities = Spark.Dsl.Extension.get_entities(owner_module, [:tools])
    plugin_entities = Spark.Dsl.Extension.get_entities(owner_module, [:plugins])
    skill_entities = Spark.Dsl.Extension.get_entities(owner_module, [:skills])

    configured_subagents =
      owner_module
      |> section_entities([:subagents], &match?(%Moto.Agent.Dsl.Subagent{}, &1))
      |> resolve_subagents!(owner_module)

    configured_memory = resolve_memory_config!(owner_module)

    skill_refs =
      Enum.filter(
        skill_entities,
        &(match?(%Moto.Agent.Dsl.SkillRef{}, &1) or
            match?(%Moto.Agent.Dsl.SkillPath{}, &1))
      )

    configured_skills = resolve_skills!(owner_module, skill_refs, Path.dirname(env.file))

    configured_mcp_tools =
      tool_entities
      |> Enum.filter(&match?(%Moto.Agent.Dsl.MCPTools{}, &1))
      |> resolve_mcp!(owner_module)

    configured_hooks =
      owner_module
      |> section_entities(
        [:hooks],
        &(match?(%Moto.Agent.Dsl.BeforeTurnHook{}, &1) or
            match?(%Moto.Agent.Dsl.AfterTurnHook{}, &1) or
            match?(%Moto.Agent.Dsl.InterruptHook{}, &1))
      )
      |> hooks_stage_map()
      |> resolve_hooks!(owner_module)

    configured_guardrails =
      owner_module
      |> section_entities(
        [:guardrails],
        &(match?(%Moto.Agent.Dsl.InputGuardrail{}, &1) or
            match?(%Moto.Agent.Dsl.OutputGuardrail{}, &1) or
            match?(%Moto.Agent.Dsl.ToolGuardrail{}, &1))
      )
      |> guardrails_stage_map()
      |> resolve_guardrails!(owner_module)

    configured_context_schema =
      owner_module
      |> Spark.Dsl.Extension.get_opt([:agent], :schema)
      |> resolve_context_schema!(owner_module)

    configured_context = resolve_context_defaults!(owner_module, configured_context_schema)

    direct_tool_modules =
      tool_entities
      |> Enum.filter(&match?(%Moto.Agent.Dsl.Tool{}, &1))
      |> Enum.map(& &1.module)

    ash_resources =
      tool_entities
      |> Enum.filter(&match?(%Moto.Agent.Dsl.AshResource{}, &1))
      |> Enum.map(& &1.resource)

    plugin_modules =
      plugin_entities
      |> Enum.filter(&match?(%Moto.Agent.Dsl.Plugin{}, &1))
      |> Enum.map(& &1.module)

    direct_tool_names = resolve_tool_names!(owner_module, direct_tool_modules, [:tools, :tool])

    {plugin_names, plugin_tool_modules, plugin_tool_names} =
      resolve_plugin_tools!(owner_module, plugin_modules)

    {skill_names, skill_tool_modules, skill_tool_names} =
      resolve_skill_tools!(owner_module, configured_skills)

    ash_resource_info = resolve_ash_resources!(owner_module, ash_resources)

    subagent_tool_modules =
      configured_subagents
      |> Enum.with_index()
      |> Enum.map(fn {subagent, index} ->
        Moto.Subagent.tool_module(owner_module, subagent, index)
      end)

    subagent_tool_names = Enum.map(configured_subagents, & &1.name)

    runtime_plugins = Moto.Agent.Runtime.runtime_plugins(plugin_modules, configured_memory)

    tool_modules =
      direct_tool_modules ++
        ash_resource_info.tool_modules ++
        skill_tool_modules ++
        plugin_tool_modules ++
        subagent_tool_modules

    tool_names =
      direct_tool_names ++
        ash_resource_info.tool_names ++
        skill_tool_names ++
        plugin_tool_names ++
        subagent_tool_names

    ensure_unique_tool_names!(owner_module, tool_names)

    runtime_module = Module.concat(owner_module, Runtime)
    request_transformer_module = Module.concat(owner_module, RuntimeRequestTransformer)

    request_transformer_system_prompt = dynamic_system_prompt || runtime_system_prompt

    effective_request_transformer =
      if is_nil(dynamic_system_prompt) and
           not Moto.Memory.requires_request_transformer?(configured_memory) and
           not Moto.Skill.requires_request_transformer?(configured_skills) do
        nil
      else
        request_transformer_module
      end

    ash_tool_config = ash_tool_config(ash_resource_info)

    public_definition = %{
      kind: :agent_definition,
      module: owner_module,
      runtime_module: runtime_module,
      name: name,
      system_prompt: configured_system_prompt,
      request_transformer: effective_request_transformer,
      configured_model: configured_model,
      model: resolved_model,
      context_schema: configured_context_schema,
      context: configured_context,
      memory: configured_memory,
      skills: configured_skills,
      tools: tool_modules,
      tool_names: tool_names,
      mcp_tools: configured_mcp_tools,
      subagents: configured_subagents,
      subagent_names: subagent_tool_names,
      plugins: plugin_modules,
      plugin_names: plugin_names,
      hooks: configured_hooks,
      guardrails: configured_guardrails,
      ash_resources: ash_resource_info.resources,
      ash_domain: ash_resource_info.domain,
      requires_actor?: ash_resource_info.require_actor?
    }

    %{
      module: owner_module,
      runtime_module: runtime_module,
      request_transformer_module: request_transformer_module,
      request_transformer_system_prompt: request_transformer_system_prompt,
      runtime_system_prompt: runtime_system_prompt,
      effective_request_transformer: effective_request_transformer,
      name: name,
      model: resolved_model,
      configured_model: configured_model,
      configured_system_prompt: configured_system_prompt,
      context_schema: configured_context_schema,
      context: configured_context,
      memory: configured_memory,
      skills: configured_skills,
      skill_names: skill_names,
      mcp_tools: configured_mcp_tools,
      subagents: configured_subagents,
      subagent_tool_modules: subagent_tool_modules,
      subagent_names: subagent_tool_names,
      runtime_plugins: runtime_plugins,
      plugins: plugin_modules,
      plugin_names: plugin_names,
      tools: tool_modules,
      tool_names: tool_names,
      hooks: configured_hooks,
      guardrails: configured_guardrails,
      ash_resources: ash_resource_info.resources,
      ash_domain: ash_resource_info.domain,
      requires_actor?: ash_resource_info.require_actor?,
      ash_tool_config: ash_tool_config,
      public_definition: public_definition
    }
  end

  defp resolve_model!(owner_module, model) do
    Moto.model(model)
  rescue
    error in [ArgumentError] ->
      raise Spark.Error.DslError,
        message: Exception.message(error),
        path: [:agent, :model],
        module: owner_module
  end

  defp resolve_system_prompt!(owner_module, system_prompt) do
    case Moto.Agent.SystemPrompt.normalize(owner_module, system_prompt) do
      {:ok, normalized} ->
        normalized

      {:error, message} ->
        raise Spark.Error.DslError,
          message: message,
          path: [:agent, :system_prompt],
          module: owner_module
    end
  end

  defp resolve_hooks!(hooks, owner_module) do
    case Moto.Hooks.normalize_dsl_hooks(hooks) do
      {:ok, normalized} ->
        normalized

      {:error, message} ->
        raise Spark.Error.DslError,
          message: message,
          path: [:hooks],
          module: owner_module
    end
  end

  defp resolve_guardrails!(guardrails, owner_module) do
    case Moto.Guardrails.normalize_dsl_guardrails(guardrails) do
      {:ok, normalized} ->
        normalized

      {:error, message} ->
        raise Spark.Error.DslError,
          message: message,
          path: [:guardrails],
          module: owner_module
    end
  end

  defp resolve_context_schema!(nil, _owner_module), do: nil

  defp resolve_context_schema!(schema, owner_module) do
    case Moto.Context.validate_schema(schema) do
      :ok ->
        schema

      {:error, reason} ->
        raise Spark.Error.DslError,
          message: context_schema_error(reason),
          path: [:agent, :schema],
          module: owner_module
    end
  end

  defp resolve_context_defaults!(owner_module, schema) do
    case Moto.Context.defaults(schema) do
      {:ok, context} ->
        context

      {:error, reason} ->
        raise Spark.Error.DslError,
          message: context_schema_error(reason),
          path: [:agent, :schema],
          module: owner_module
    end
  end

  defp resolve_memory_config!(owner_module) do
    memory_entities =
      section_entities(
        owner_module,
        [:memory],
        &(match?(%Moto.Agent.Dsl.MemoryMode{}, &1) or
            match?(%Moto.Agent.Dsl.MemoryNamespace{}, &1) or
            match?(%Moto.Agent.Dsl.MemorySharedNamespace{}, &1) or
            match?(%Moto.Agent.Dsl.MemoryCapture{}, &1) or
            match?(%Moto.Agent.Dsl.MemoryInject{}, &1) or
            match?(%Moto.Agent.Dsl.MemoryRetrieve{}, &1))
      )

    memory_section_anno =
      owner_module
      |> Module.get_attribute(:spark_dsl_config)
      |> case do
        %{} = dsl -> Spark.Dsl.Extension.get_section_anno(dsl, [:memory])
        _ -> nil
      end

    cond do
      memory_entities != [] ->
        resolve_memory!(owner_module, memory_entities)

      not is_nil(memory_section_anno) ->
        Moto.Memory.default_config()

      true ->
        nil
    end
  end

  defp resolve_memory!(owner_module, entries) when is_list(entries) do
    case Moto.Memory.normalize_dsl(entries) do
      {:ok, normalized} ->
        normalized

      {:error, message} ->
        raise Spark.Error.DslError,
          message: message,
          path: [:memory],
          module: owner_module
    end
  end

  defp resolve_skills!(owner_module, entries, base_dir)
       when is_list(entries) and is_binary(base_dir) do
    case Moto.Skill.normalize_dsl(entries, base_dir) do
      {:ok, normalized} ->
        normalized

      {:error, message} ->
        raise Spark.Error.DslError,
          message: message,
          path: [:skills],
          module: owner_module
    end
  end

  defp resolve_mcp!(entries, owner_module) when is_list(entries) do
    case Moto.MCP.normalize_dsl(entries) do
      {:ok, normalized} ->
        normalized

      {:error, message} ->
        raise Spark.Error.DslError,
          message: message,
          path: [:tools, :mcp_tools],
          module: owner_module
    end
  end

  defp resolve_subagents!(entries, owner_module) when is_list(entries) do
    entries
    |> Enum.reduce_while({:ok, []}, fn %Moto.Agent.Dsl.Subagent{} = entry, {:ok, acc} ->
      case Moto.Subagent.new(
             entry.agent,
             as: entry.as,
             description: entry.description,
             target: entry.target,
             timeout: entry.timeout,
             forward_context: entry.forward_context,
             result: entry.result
           ) do
        {:ok, subagent} ->
          {:cont, {:ok, acc ++ [subagent]}}

        {:error, message} ->
          {:halt, {:error, message}}
      end
    end)
    |> case do
      {:ok, subagents} ->
        case Moto.Subagent.subagent_names(subagents) do
          {:ok, _names} ->
            subagents

          {:error, message} ->
            raise Spark.Error.DslError,
              message: message,
              path: [:subagents],
              module: owner_module
        end

      {:error, message} ->
        raise Spark.Error.DslError,
          message: message,
          path: [:subagents],
          module: owner_module
    end
  end

  defp resolve_tool_names!(owner_module, tool_modules, path) do
    case Moto.Tool.tool_names(tool_modules) do
      {:ok, tool_names} ->
        tool_names

      {:error, message} ->
        raise Spark.Error.DslError,
          message: message,
          path: path,
          module: owner_module
    end
  end

  defp resolve_plugin_tools!(owner_module, plugin_modules) do
    plugin_names =
      case Moto.Plugin.plugin_names(plugin_modules) do
        {:ok, plugin_names} ->
          plugin_names

        {:error, message} ->
          raise Spark.Error.DslError,
            message: message,
            path: [:plugins, :plugin],
            module: owner_module
      end

    plugin_tool_modules =
      case Moto.Plugin.plugin_actions(plugin_modules) do
        {:ok, plugin_tool_modules} ->
          plugin_tool_modules

        {:error, message} ->
          raise Spark.Error.DslError,
            message: message,
            path: [:plugins, :plugin],
            module: owner_module
      end

    plugin_tool_names =
      case Moto.Tool.action_names(plugin_tool_modules) do
        {:ok, plugin_tool_names} ->
          plugin_tool_names

        {:error, message} ->
          raise Spark.Error.DslError,
            message: message,
            path: [:plugins, :plugin],
            module: owner_module
      end

    {plugin_names, plugin_tool_modules, plugin_tool_names}
  end

  defp resolve_skill_tools!(owner_module, configured_skills) do
    skill_tool_modules = Moto.Skill.action_modules(configured_skills)

    case Moto.Tool.action_names(skill_tool_modules) do
      {:ok, skill_tool_names} ->
        {Moto.Skill.skill_names(configured_skills), skill_tool_modules, skill_tool_names}

      {:error, message} ->
        raise Spark.Error.DslError,
          message: message,
          path: [:skills, :skill],
          module: owner_module
    end
  end

  defp resolve_ash_resources!(owner_module, ash_resources) do
    case Moto.Agent.AshResources.expand(ash_resources) do
      {:ok, ash_resource_info} ->
        ash_resource_info

      {:error, message} ->
        raise Spark.Error.DslError,
          message: message,
          path: [:tools, :ash_resource],
          module: owner_module
    end
  end

  defp hooks_stage_map(hook_entities) do
    Enum.reduce(hook_entities, Moto.Hooks.default_stage_map(), fn
      %Moto.Agent.Dsl.BeforeTurnHook{hook: hook}, acc ->
        Map.update!(acc, :before_turn, &(&1 ++ [hook]))

      %Moto.Agent.Dsl.AfterTurnHook{hook: hook}, acc ->
        Map.update!(acc, :after_turn, &(&1 ++ [hook]))

      %Moto.Agent.Dsl.InterruptHook{hook: hook}, acc ->
        Map.update!(acc, :on_interrupt, &(&1 ++ [hook]))
    end)
  end

  defp guardrails_stage_map(guardrail_entities) do
    Enum.reduce(guardrail_entities, Moto.Guardrails.default_stage_map(), fn
      %Moto.Agent.Dsl.InputGuardrail{guardrail: guardrail}, acc ->
        Map.update!(acc, :input, &(&1 ++ [guardrail]))

      %Moto.Agent.Dsl.OutputGuardrail{guardrail: guardrail}, acc ->
        Map.update!(acc, :output, &(&1 ++ [guardrail]))

      %Moto.Agent.Dsl.ToolGuardrail{guardrail: guardrail}, acc ->
        Map.update!(acc, :tool, &(&1 ++ [guardrail]))
    end)
  end

  defp section_entities(owner_module, path, predicate) when is_function(predicate, 1) do
    owner_module
    |> Spark.Dsl.Extension.get_entities(path)
    |> Enum.filter(predicate)
  end

  defp ensure_unique_tool_names!(owner_module, tool_names) do
    if Enum.uniq(tool_names) != tool_names do
      duplicates =
        tool_names
        |> Enum.frequencies()
        |> Enum.filter(fn {_name, count} -> count > 1 end)
        |> Enum.map(&elem(&1, 0))
        |> Enum.sort()

      raise Spark.Error.DslError,
        message: "duplicate tool names in Moto agent: #{Enum.join(duplicates, ", ")}",
        path: [:tools],
        module: owner_module
    end
  end

  defp ash_tool_config(%{resources: []}), do: nil

  defp ash_tool_config(ash_resource_info) do
    %{
      resources: ash_resource_info.resources,
      domain: ash_resource_info.domain,
      require_actor?: true
    }
  end

  defp context_schema_error({:invalid_context_schema, :expected_zoi_schema}),
    do: "agent schema must be a Zoi map/object schema"

  defp context_schema_error({:invalid_context_schema, :expected_zoi_map_schema}),
    do: "agent schema must be a Zoi map/object schema"

  defp context_schema_error({:invalid_context_schema, {:expected_map_result, other}}),
    do: "agent schema must parse context to a map, got: #{inspect(other)}"

  defp context_schema_error(reason), do: inspect(reason)
end
