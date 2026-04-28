defmodule Jidoka.Agent.Definition do
  @moduledoc false

  @type t :: map()

  @spec build!(Macro.Env.t()) :: t()
  def build!(%Macro.Env{} = env) do
    owner_module = env.module

    reject_legacy_placements!(owner_module)

    configured_id = Spark.Dsl.Extension.get_opt(owner_module, [:agent], :id)
    id = resolve_agent_id!(owner_module, configured_id)
    description = Spark.Dsl.Extension.get_opt(owner_module, [:agent], :description)

    configured_model = Spark.Dsl.Extension.get_opt(owner_module, [:defaults], :model, :fast)
    resolved_model = resolve_model!(owner_module, configured_model)
    configured_instructions = Spark.Dsl.Extension.get_opt(owner_module, [:defaults], :instructions)
    configured_character = Spark.Dsl.Extension.get_opt(owner_module, [:defaults], :character)

    require_instructions!(owner_module, configured_instructions)
    character_spec = resolve_character!(owner_module, configured_character)

    {runtime_system_prompt, dynamic_system_prompt} =
      case resolve_instructions!(owner_module, configured_instructions) do
        {:static, prompt} ->
          {prompt, nil}

        {:dynamic, spec} ->
          {nil, spec}
      end

    configured_context_schema =
      owner_module
      |> Spark.Dsl.Extension.get_opt([:agent], :schema)
      |> resolve_context_schema!(owner_module)

    configured_context = resolve_context_defaults!(owner_module, configured_context_schema)
    configured_output = resolve_output_config!(owner_module)

    capability_entities = Spark.Dsl.Extension.get_entities(owner_module, [:capabilities])

    configured_subagents =
      owner_module
      |> section_entities([:capabilities], &match?(%Jidoka.Agent.Dsl.Subagent{}, &1))
      |> resolve_subagents!(owner_module)

    configured_workflows =
      owner_module
      |> section_entities([:capabilities], &match?(%Jidoka.Agent.Dsl.Workflow{}, &1))
      |> resolve_workflows!(owner_module)

    configured_handoffs =
      owner_module
      |> section_entities([:capabilities], &match?(%Jidoka.Agent.Dsl.Handoff{}, &1))
      |> resolve_handoffs!(owner_module)

    configured_memory =
      owner_module
      |> resolve_memory_config!(configured_context_schema)

    skill_refs =
      Enum.filter(
        capability_entities,
        &(match?(%Jidoka.Agent.Dsl.SkillRef{}, &1) or
            match?(%Jidoka.Agent.Dsl.SkillPath{}, &1))
      )

    configured_skills = resolve_skills!(owner_module, skill_refs, Path.dirname(env.file))

    configured_mcp_tools =
      capability_entities
      |> Enum.filter(&match?(%Jidoka.Agent.Dsl.MCPTools{}, &1))
      |> resolve_mcp!(owner_module)

    configured_web =
      capability_entities
      |> Enum.filter(&match?(%Jidoka.Agent.Dsl.Web{}, &1))
      |> resolve_web!(owner_module)

    configured_hooks =
      owner_module
      |> section_entities(
        [:lifecycle],
        &(match?(%Jidoka.Agent.Dsl.BeforeTurnHook{}, &1) or
            match?(%Jidoka.Agent.Dsl.AfterTurnHook{}, &1) or
            match?(%Jidoka.Agent.Dsl.InterruptHook{}, &1))
      )
      |> hooks_stage_map()
      |> resolve_hooks!(owner_module)

    configured_guardrails =
      owner_module
      |> section_entities(
        [:lifecycle],
        &(match?(%Jidoka.Agent.Dsl.InputGuardrail{}, &1) or
            match?(%Jidoka.Agent.Dsl.OutputGuardrail{}, &1) or
            match?(%Jidoka.Agent.Dsl.ToolGuardrail{}, &1))
      )
      |> guardrails_stage_map()
      |> resolve_guardrails!(owner_module)

    direct_tool_modules =
      capability_entities
      |> Enum.filter(&match?(%Jidoka.Agent.Dsl.Tool{}, &1))
      |> Enum.map(& &1.module)

    ash_resources =
      capability_entities
      |> Enum.filter(&match?(%Jidoka.Agent.Dsl.AshResource{}, &1))
      |> Enum.map(& &1.resource)

    plugin_modules =
      capability_entities
      |> Enum.filter(&match?(%Jidoka.Agent.Dsl.Plugin{}, &1))
      |> Enum.map(& &1.module)

    direct_tool_names = resolve_tool_names!(owner_module, direct_tool_modules, [:capabilities, :tool])

    {plugin_names, plugin_tool_modules, plugin_tool_names} =
      resolve_plugin_tools!(owner_module, plugin_modules)

    web_tool_modules = Jidoka.Web.tool_modules(configured_web)

    web_tool_names =
      resolve_web_tool_names!(owner_module, configured_web)

    {skill_names, skill_tool_modules, skill_tool_names} =
      resolve_skill_tools!(owner_module, configured_skills)

    ash_resource_info = resolve_ash_resources!(owner_module, ash_resources)

    subagent_tool_modules =
      configured_subagents
      |> Enum.with_index()
      |> Enum.map(fn {subagent, index} ->
        Jidoka.Subagent.tool_module(owner_module, subagent, index)
      end)

    subagent_tool_names = Enum.map(configured_subagents, & &1.name)

    workflow_tool_modules =
      configured_workflows
      |> Enum.with_index()
      |> Enum.map(fn {workflow, index} ->
        Jidoka.Workflow.Capability.tool_module(owner_module, workflow, index)
      end)

    workflow_tool_names = Enum.map(configured_workflows, & &1.name)

    handoff_tool_modules =
      configured_handoffs
      |> Enum.with_index()
      |> Enum.map(fn {handoff, index} ->
        Jidoka.Handoff.Capability.tool_module(owner_module, handoff, index)
      end)

    handoff_tool_names = Enum.map(configured_handoffs, & &1.name)

    runtime_plugins = Jidoka.Agent.Runtime.runtime_plugins(plugin_modules, configured_memory)

    tool_modules =
      direct_tool_modules ++
        ash_resource_info.tool_modules ++
        skill_tool_modules ++
        plugin_tool_modules ++
        web_tool_modules ++
        subagent_tool_modules ++
        workflow_tool_modules ++
        handoff_tool_modules

    tool_names =
      direct_tool_names ++
        ash_resource_info.tool_names ++
        skill_tool_names ++
        plugin_tool_names ++
        web_tool_names ++
        subagent_tool_names ++
        workflow_tool_names ++
        handoff_tool_names

    ensure_unique_tool_names!(owner_module, tool_names)

    runtime_module = Module.concat(owner_module, Runtime)
    request_transformer_module = Module.concat(owner_module, RuntimeRequestTransformer)

    request_transformer_system_prompt = dynamic_system_prompt || runtime_system_prompt
    effective_request_transformer = request_transformer_module

    ash_tool_config = ash_tool_config(ash_resource_info)

    public_definition = %{
      kind: :agent_definition,
      module: owner_module,
      runtime_module: runtime_module,
      id: id,
      name: id,
      description: description,
      instructions: configured_instructions,
      character: configured_character,
      character_spec: character_spec,
      request_transformer: effective_request_transformer,
      configured_model: configured_model,
      model: resolved_model,
      context_schema: configured_context_schema,
      context: configured_context,
      output: configured_output,
      memory: configured_memory,
      skills: configured_skills,
      tools: tool_modules,
      tool_names: tool_names,
      mcp_tools: configured_mcp_tools,
      web: configured_web,
      web_tool_names: web_tool_names,
      subagents: configured_subagents,
      subagent_names: subagent_tool_names,
      workflows: configured_workflows,
      workflow_names: workflow_tool_names,
      handoffs: configured_handoffs,
      handoff_names: handoff_tool_names,
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
      id: id,
      name: id,
      description: description,
      model: resolved_model,
      configured_model: configured_model,
      configured_instructions: configured_instructions,
      configured_character: configured_character,
      character_spec: character_spec,
      context_schema: configured_context_schema,
      context: configured_context,
      output: configured_output,
      memory: configured_memory,
      skills: configured_skills,
      skill_names: skill_names,
      mcp_tools: configured_mcp_tools,
      web: configured_web,
      web_tool_modules: web_tool_modules,
      web_tool_names: web_tool_names,
      subagents: configured_subagents,
      subagent_tool_modules: subagent_tool_modules,
      subagent_names: subagent_tool_names,
      workflows: configured_workflows,
      workflow_tool_modules: workflow_tool_modules,
      workflow_names: workflow_tool_names,
      handoffs: configured_handoffs,
      handoff_tool_modules: handoff_tool_modules,
      handoff_names: handoff_tool_names,
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

  @legacy_sections [
    memory: "Move `memory do ... end` inside `lifecycle do ... end`.",
    tools: "Move `tool`, `ash_resource`, and `mcp_tools` declarations inside `capabilities do ... end`.",
    skills: "Move `skill` and `load_path` declarations inside `capabilities do ... end`.",
    plugins: "Move `plugin` declarations inside `capabilities do ... end`.",
    subagents: "Move `subagent` declarations inside `capabilities do ... end`.",
    handoffs: "Move `handoff` declarations inside `capabilities do ... end`.",
    hooks: "Move hook declarations inside `lifecycle do ... end`.",
    guardrails:
      "Move guardrails inside `lifecycle do ... end` and rename `input`, `output`, and `tool` to `input_guardrail`, `output_guardrail`, and `tool_guardrail`."
  ]

  defp reject_legacy_placements!(owner_module) do
    reject_legacy_agent_option!(
      owner_module,
      :model,
      "Move `model` into `defaults do ... end`."
    )

    reject_legacy_agent_option!(
      owner_module,
      :system_prompt,
      "Rename `system_prompt` to `instructions` inside `defaults do ... end`."
    )

    Enum.each(@legacy_sections, fn {section, hint} ->
      if legacy_section_present?(owner_module, section) do
        raise Jidoka.Agent.Dsl.Error.exception(
                message: "Top-level `#{section} do ... end` is not valid in the beta Jidoka DSL.",
                path: [section],
                hint: hint,
                module: owner_module,
                location: Spark.Dsl.Extension.get_section_anno(owner_module, [section])
              )
      end
    end)
  end

  defp resolve_handoffs!(entities, owner_module) do
    handoffs =
      Enum.map(entities, fn entity ->
        case Jidoka.Handoff.Capability.new(entity.agent,
               as: entity.as,
               description: entity.description,
               target: entity.target,
               forward_context: entity.forward_context
             ) do
          {:ok, handoff} ->
            handoff

          {:error, message} ->
            raise Jidoka.Agent.Dsl.Error.exception(
                    message: message,
                    path: [:capabilities, :handoff],
                    value: entity.agent,
                    hint: "Use a compiled Jidoka agent module and valid handoff options.",
                    module: owner_module
                  )
        end
      end)

    case Jidoka.Handoff.Capability.handoff_names(handoffs) do
      {:ok, _names} ->
        handoffs

      {:error, message} ->
        raise Jidoka.Agent.Dsl.Error.exception(
                message: message,
                path: [:capabilities, :handoff],
                value: Enum.map(handoffs, & &1.name),
                hint: "Give each handoff a unique `as:` name.",
                module: owner_module
              )
    end
  end

  defp reject_legacy_agent_option!(owner_module, option, hint) do
    value = Spark.Dsl.Extension.get_opt(owner_module, [:agent], option)

    unless is_nil(value) do
      raise Jidoka.Agent.Dsl.Error.exception(
              message: "`agent.#{option}` is not valid in the beta Jidoka DSL.",
              path: [:agent, option],
              value: value,
              hint: hint,
              module: owner_module
            )
    end
  end

  defp legacy_section_present?(owner_module, section) do
    Spark.Dsl.Extension.get_entities(owner_module, [section]) != [] or
      not is_nil(Spark.Dsl.Extension.get_section_anno(owner_module, [section]))
  rescue
    _ -> false
  end

  defp resolve_agent_id!(owner_module, id) do
    normalized_id =
      cond do
        is_atom(id) and not is_nil(id) ->
          Atom.to_string(id)

        is_binary(id) ->
          String.trim(id)

        true ->
          raise Jidoka.Agent.Dsl.Error.exception(
                  message: "`agent.id` is required.",
                  path: [:agent, :id],
                  value: id,
                  hint: "Declare `agent do id :my_agent end` using lower snake case.",
                  module: owner_module
                )
      end

    if Regex.match?(~r/^[a-z][a-z0-9_]*$/, normalized_id) do
      normalized_id
    else
      raise Jidoka.Agent.Dsl.Error.exception(
              message: "`agent.id` must be lower snake case.",
              path: [:agent, :id],
              value: id,
              hint: "Use a value like `support_agent` with lowercase letters, numbers, and underscores.",
              module: owner_module
            )
    end
  end

  defp require_instructions!(owner_module, nil) do
    raise Jidoka.Agent.Dsl.Error.exception(
            message: "`defaults.instructions` is required.",
            path: [:defaults, :instructions],
            value: nil,
            hint: "Declare `defaults do instructions \"...\" end` or provide a resolver module/MFA.",
            module: owner_module
          )
  end

  defp require_instructions!(_owner_module, _instructions), do: :ok

  defp resolve_model!(owner_module, model) do
    Jidoka.model(model)
  rescue
    error in [ArgumentError] ->
      raise Jidoka.Agent.Dsl.Error.exception(
              message: Exception.message(error),
              path: [:defaults, :model],
              value: model,
              hint: "Use a configured Jidoka model alias such as `:fast` or a Jido.AI-compatible model spec.",
              module: owner_module
            )
  end

  defp resolve_instructions!(owner_module, instructions) do
    case Jidoka.Agent.SystemPrompt.normalize(owner_module, instructions, label: "instructions") do
      {:ok, normalized} ->
        normalized

      {:error, message} ->
        raise Jidoka.Agent.Dsl.Error.exception(
                message: message,
                path: [:defaults, :instructions],
                value: instructions,
                hint: "Use a non-empty string, a module implementing `resolve_system_prompt/1`, or an MFA tuple.",
                module: owner_module
              )
    end
  end

  defp resolve_character!(_owner_module, nil), do: nil

  defp resolve_character!(owner_module, character) do
    case Jidoka.Character.normalize(owner_module, character, label: "character") do
      {:ok, normalized} ->
        normalized

      {:error, message} ->
        raise Jidoka.Agent.Dsl.Error.exception(
                message: message,
                path: [:defaults, :character],
                value: character,
                hint: "Use an inline `Jido.Character` map or a `use Jido.Character` module.",
                module: owner_module
              )
    end
  end

  defp resolve_hooks!(hooks, owner_module) do
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

  defp resolve_guardrails!(guardrails, owner_module) do
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

  defp resolve_context_schema!(nil, _owner_module), do: nil

  defp resolve_context_schema!(schema, owner_module) do
    case Jidoka.Context.validate_schema(schema) do
      :ok ->
        schema

      {:error, reason} ->
        raise Jidoka.Agent.Dsl.Error.exception(
                message: context_schema_error(reason),
                path: [:agent, :schema],
                value: schema,
                hint: "Use a compiled Zoi map/object schema owned by the agent DSL.",
                module: owner_module
              )
    end
  end

  defp resolve_context_defaults!(owner_module, schema) do
    case Jidoka.Context.defaults(schema) do
      {:ok, context} ->
        context

      {:error, reason} ->
        raise Jidoka.Agent.Dsl.Error.exception(
                message: context_schema_error(reason),
                path: [:agent, :schema],
                hint: "Ensure the Zoi schema parses an empty input to map defaults.",
                module: owner_module
              )
    end
  end

  defp resolve_output_config!(owner_module) do
    schema = Spark.Dsl.Extension.get_opt(owner_module, [:agent, :output], :schema)

    if is_nil(schema) do
      nil
    else
      retries = Spark.Dsl.Extension.get_opt(owner_module, [:agent, :output], :retries, 1)
      mode = Spark.Dsl.Extension.get_opt(owner_module, [:agent, :output], :on_validation_error, :repair)

      case Jidoka.Output.new(schema: schema, retries: retries, on_validation_error: mode) do
        {:ok, %Jidoka.Output{schema_kind: :zoi} = output} ->
          output

        {:ok, %Jidoka.Output{schema_kind: :json_schema}} ->
          raise_output_error!(
            owner_module,
            "agent.output.schema must be a Zoi object/map schema in the Elixir DSL.",
            schema,
            "Use `schema Zoi.object(%{...})`. JSON Schema maps are only accepted in imported specs."
          )

        {:error, message} ->
          raise_output_error!(
            owner_module,
            message,
            schema,
            "Use `output do schema Zoi.object(%{...}) end` with non-negative retries and :repair or :error mode."
          )
      end
    end
  end

  defp raise_output_error!(owner_module, message, value, hint) do
    raise Jidoka.Agent.Dsl.Error.exception(
            message: message,
            path: [:agent, :output],
            value: value,
            hint: hint,
            module: owner_module,
            location: Spark.Dsl.Extension.get_section_anno(owner_module, [:agent, :output])
          )
  end

  defp resolve_memory_config!(owner_module, context_schema) do
    memory_entities =
      section_entities(
        owner_module,
        [:lifecycle, :memory],
        &(match?(%Jidoka.Agent.Dsl.MemoryMode{}, &1) or
            match?(%Jidoka.Agent.Dsl.MemoryNamespace{}, &1) or
            match?(%Jidoka.Agent.Dsl.MemorySharedNamespace{}, &1) or
            match?(%Jidoka.Agent.Dsl.MemoryCapture{}, &1) or
            match?(%Jidoka.Agent.Dsl.MemoryInject{}, &1) or
            match?(%Jidoka.Agent.Dsl.MemoryRetrieve{}, &1))
      )

    memory_section_anno =
      owner_module
      |> Module.get_attribute(:spark_dsl_config)
      |> case do
        %{} = dsl -> Spark.Dsl.Extension.get_section_anno(dsl, [:lifecycle, :memory])
        _ -> nil
      end

    cond do
      memory_entities != [] ->
        owner_module
        |> resolve_memory!(memory_entities)
        |> validate_memory_namespace_context!(owner_module, context_schema)

      not is_nil(memory_section_anno) ->
        owner_module
        |> then(fn _ -> Jidoka.Memory.default_config() end)
        |> validate_memory_namespace_context!(owner_module, context_schema)

      true ->
        nil
    end
  end

  defp resolve_memory!(owner_module, entries) when is_list(entries) do
    case Jidoka.Memory.normalize_dsl(entries) do
      {:ok, normalized} ->
        normalized

      {:error, message} ->
        raise Jidoka.Agent.Dsl.Error.exception(
                message: message,
                path: [:lifecycle, :memory],
                hint: "Declare each memory setting once and keep shared namespace settings consistent.",
                module: owner_module
              )
    end
  end

  defp validate_memory_namespace_context!(nil, _owner_module, _context_schema), do: nil

  defp validate_memory_namespace_context!(%{namespace: {:context, key}} = memory, owner_module, context_schema)
       when not is_nil(context_schema) do
    if Jidoka.Context.schema_has_key?(context_schema, key) do
      memory
    else
      raise Jidoka.Agent.Dsl.Error.exception(
              message: "memory context namespace key is not declared by `agent.schema`.",
              path: [:lifecycle, :memory, :namespace],
              value: {:context, key},
              hint: "Add #{inspect(key)} to the Zoi schema or use `namespace :per_agent`/`:shared`.",
              module: owner_module
            )
    end
  end

  defp validate_memory_namespace_context!(memory, _owner_module, _context_schema), do: memory

  defp resolve_skills!(owner_module, entries, base_dir)
       when is_list(entries) and is_binary(base_dir) do
    case Jidoka.Skill.normalize_dsl(entries, base_dir) do
      {:ok, normalized} ->
        normalized

      {:error, message} ->
        raise Jidoka.Agent.Dsl.Error.exception(
                message: message,
                path: [:capabilities],
                hint: "Declare skills with `skill` or `load_path` inside `capabilities`.",
                module: owner_module
              )
    end
  end

  defp resolve_mcp!(entries, owner_module) when is_list(entries) do
    case Jidoka.MCP.normalize_dsl(entries) do
      {:ok, normalized} ->
        normalized

      {:error, message} ->
        raise Jidoka.Agent.Dsl.Error.exception(
                message: message,
                path: [:capabilities, :mcp_tools],
                hint: "Declare MCP endpoints as `mcp_tools endpoint: ...` inside `capabilities`.",
                module: owner_module
              )
    end
  end

  defp resolve_web!(entries, owner_module) when is_list(entries) do
    case Jidoka.Web.normalize_dsl(entries) do
      {:ok, normalized} ->
        normalized

      {:error, message} ->
        raise Jidoka.Agent.Dsl.Error.exception(
                message: message,
                path: [:capabilities, :web],
                hint: "Declare `web :search` or `web :read_only` at most once inside `capabilities`.",
                module: owner_module
              )
    end
  end

  defp resolve_subagents!(entries, owner_module) when is_list(entries) do
    entries
    |> Enum.reduce_while({:ok, []}, fn %Jidoka.Agent.Dsl.Subagent{} = entry, {:ok, acc} ->
      case Jidoka.Subagent.new(
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
        case Jidoka.Subagent.subagent_names(subagents) do
          {:ok, _names} ->
            subagents

          {:error, message} ->
            raise Jidoka.Agent.Dsl.Error.exception(
                    message: message,
                    path: [:capabilities, :subagent],
                    hint: "Give each subagent a unique published tool name.",
                    module: owner_module
                  )
        end

      {:error, message} ->
        raise Jidoka.Agent.Dsl.Error.exception(
                message: message,
                path: [:capabilities, :subagent],
                hint: "Declare subagents inside `capabilities` with a Jidoka-compatible module.",
                module: owner_module
              )
    end
  end

  defp resolve_workflows!(entries, owner_module) when is_list(entries) do
    entries
    |> Enum.reduce_while({:ok, []}, fn %Jidoka.Agent.Dsl.Workflow{} = entry, {:ok, acc} ->
      case Jidoka.Workflow.Capability.new(
             entry.workflow,
             as: entry.as,
             description: entry.description,
             timeout: entry.timeout,
             forward_context: entry.forward_context,
             result: entry.result
           ) do
        {:ok, workflow} ->
          {:cont, {:ok, acc ++ [workflow]}}

        {:error, message} ->
          {:halt, {:error, message}}
      end
    end)
    |> case do
      {:ok, workflows} ->
        case Jidoka.Workflow.Capability.workflow_names(workflows) do
          {:ok, _names} ->
            workflows

          {:error, message} ->
            raise Jidoka.Agent.Dsl.Error.exception(
                    message: message,
                    path: [:capabilities, :workflow],
                    hint: "Give each workflow capability a unique published tool name.",
                    module: owner_module
                  )
        end

      {:error, message} ->
        raise Jidoka.Agent.Dsl.Error.exception(
                message: message,
                path: [:capabilities, :workflow],
                hint: "Declare workflows inside `capabilities` with a Jidoka workflow module.",
                module: owner_module
              )
    end
  end

  defp resolve_tool_names!(owner_module, tool_modules, path) do
    case Jidoka.Tool.tool_names(tool_modules) do
      {:ok, tool_names} ->
        tool_names

      {:error, message} ->
        raise Jidoka.Agent.Dsl.Error.exception(
                message: message,
                path: path,
                hint: "Use Jidoka tool modules that publish valid tool names.",
                module: owner_module
              )
    end
  end

  defp resolve_plugin_tools!(owner_module, plugin_modules) do
    plugin_names =
      case Jidoka.Plugin.plugin_names(plugin_modules) do
        {:ok, plugin_names} ->
          plugin_names

        {:error, message} ->
          raise Jidoka.Agent.Dsl.Error.exception(
                  message: message,
                  path: [:capabilities, :plugin],
                  hint: "Ensure each plugin module uses `Jidoka.Plugin` and declares a unique name.",
                  module: owner_module
                )
      end

    plugin_tool_modules =
      case Jidoka.Plugin.plugin_actions(plugin_modules) do
        {:ok, plugin_tool_modules} ->
          plugin_tool_modules

        {:error, message} ->
          raise Jidoka.Agent.Dsl.Error.exception(
                  message: message,
                  path: [:capabilities, :plugin],
                  hint: "Ensure each plugin returns valid action-backed tool modules.",
                  module: owner_module
                )
      end

    plugin_tool_names =
      case Jidoka.Tool.action_names(plugin_tool_modules) do
        {:ok, plugin_tool_names} ->
          plugin_tool_names

        {:error, message} ->
          raise Jidoka.Agent.Dsl.Error.exception(
                  message: message,
                  path: [:capabilities, :plugin],
                  hint: "Plugin-provided tools must publish valid unique tool names.",
                  module: owner_module
                )
      end

    {plugin_names, plugin_tool_modules, plugin_tool_names}
  end

  defp resolve_web_tool_names!(_owner_module, []), do: []

  defp resolve_web_tool_names!(owner_module, configured_web) do
    case Jidoka.Web.tool_names(configured_web) do
      {:ok, web_tool_names} ->
        web_tool_names

      {:error, message} ->
        raise Jidoka.Agent.Dsl.Error.exception(
                message: message,
                path: [:capabilities, :web],
                hint: "Use a supported Jidoka web mode such as `web :search` or `web :read_only`.",
                module: owner_module
              )
    end
  end

  defp resolve_skill_tools!(owner_module, configured_skills) do
    skill_tool_modules = Jidoka.Skill.action_modules(configured_skills)

    case Jidoka.Tool.action_names(skill_tool_modules) do
      {:ok, skill_tool_names} ->
        {Jidoka.Skill.skill_names(configured_skills), skill_tool_modules, skill_tool_names}

      {:error, message} ->
        raise Jidoka.Agent.Dsl.Error.exception(
                message: message,
                path: [:capabilities, :skill],
                hint: "Skill-provided tools must publish valid unique tool names.",
                module: owner_module
              )
    end
  end

  defp resolve_ash_resources!(owner_module, ash_resources) do
    case Jidoka.Agent.AshResources.expand(ash_resources) do
      {:ok, ash_resource_info} ->
        ash_resource_info

      {:error, message} ->
        raise Jidoka.Agent.Dsl.Error.exception(
                message: message,
                path: [:capabilities, :ash_resource],
                hint: "Use an Ash resource extended with AshJido.",
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

      raise Jidoka.Agent.Dsl.Error.exception(
              message: "duplicate tool names in Jidoka agent: #{Enum.join(duplicates, ", ")}",
              path: [:capabilities],
              value: duplicates,
              hint:
                "Rename or remove one of the conflicting tools across direct, Ash, MCP, skill, plugin, web, subagent, workflow, and handoff sources.",
              module: owner_module
            )
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

  defp context_schema_error(%{message: message}) when is_binary(message), do: message
  defp context_schema_error(reason), do: Jidoka.format_error(reason)
end
