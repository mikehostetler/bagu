defmodule Moto.Agent.Build do
  @moduledoc false

  @spec resolve_model!(module(), term()) :: term()
  def resolve_model!(owner_module, model) do
    Moto.model(model)
  rescue
    error in [ArgumentError] ->
      raise Spark.Error.DslError,
        message: Exception.message(error),
        path: [:agent, :model],
        module: owner_module
  end

  @spec resolve_system_prompt!(module(), term()) :: Moto.Agent.SystemPrompt.spec()
  def resolve_system_prompt!(owner_module, system_prompt) do
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

  @spec resolve_hooks!(module(), Moto.Hooks.stage_map()) :: Moto.Hooks.stage_map()
  def resolve_hooks!(owner_module, hooks) do
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

  @spec resolve_guardrails!(module(), Moto.Guardrails.stage_map()) :: Moto.Guardrails.stage_map()
  def resolve_guardrails!(owner_module, guardrails) do
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

  @spec resolve_context!(module(), list()) :: map()
  def resolve_context!(owner_module, entries) when is_list(entries) do
    context =
      Enum.reduce(entries, %{}, fn %Moto.Agent.Dsl.ContextEntry{key: key, value: value}, acc ->
        Map.put(acc, key, value)
      end)

    case Moto.Context.validate_default(context) do
      :ok ->
        context

      {:error, message} ->
        raise Spark.Error.DslError,
          message: message,
          path: [:context],
          module: owner_module
    end
  end

  @spec resolve_memory!(module(), list()) :: Moto.Memory.config() | nil
  def resolve_memory!(owner_module, entries) when is_list(entries) do
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

  @spec resolve_subagents!(module(), list()) :: [Moto.Subagent.t()]
  def resolve_subagents!(owner_module, entries) when is_list(entries) do
    entries
    |> Enum.reduce_while({:ok, []}, fn %Moto.Agent.Dsl.Subagent{} = entry, {:ok, acc} ->
      case Moto.Subagent.new(
             entry.agent,
             as: entry.as,
             description: entry.description,
             target: entry.target
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

  @spec before_compile(Macro.Env.t()) :: Macro.t()
  def before_compile(env) do
    default_name =
      env.module
      |> Module.split()
      |> List.last()
      |> Macro.underscore()

    name = Spark.Dsl.Extension.get_opt(env.module, [:agent], :name, default_name)
    configured_model = Spark.Dsl.Extension.get_opt(env.module, [:agent], :model, :fast)
    resolved_model = resolve_model!(env.module, configured_model)
    configured_system_prompt = Spark.Dsl.Extension.get_opt(env.module, [:agent], :system_prompt)

    tool_entities = Spark.Dsl.Extension.get_entities(env.module, [:tools])
    plugin_entities = Spark.Dsl.Extension.get_entities(env.module, [:plugins])

    subagent_entities =
      env.module
      |> Spark.Dsl.Extension.get_entities([:subagents])
      |> Enum.filter(&match?(%Moto.Agent.Dsl.Subagent{}, &1))

    context_entities =
      env.module
      |> Spark.Dsl.Extension.get_entities([:context])
      |> Enum.filter(&match?(%Moto.Agent.Dsl.ContextEntry{}, &1))

    memory_entities =
      env.module
      |> Spark.Dsl.Extension.get_entities([:memory])
      |> Enum.filter(
        &(match?(%Moto.Agent.Dsl.MemoryMode{}, &1) or
            match?(%Moto.Agent.Dsl.MemoryNamespace{}, &1) or
            match?(%Moto.Agent.Dsl.MemorySharedNamespace{}, &1) or
            match?(%Moto.Agent.Dsl.MemoryCapture{}, &1) or
            match?(%Moto.Agent.Dsl.MemoryInject{}, &1) or
            match?(%Moto.Agent.Dsl.MemoryRetrieve{}, &1))
      )

    hook_entities =
      env.module
      |> Spark.Dsl.Extension.get_entities([:hooks])
      |> Enum.filter(
        &(match?(%Moto.Agent.Dsl.BeforeTurnHook{}, &1) or
            match?(%Moto.Agent.Dsl.AfterTurnHook{}, &1) or
            match?(%Moto.Agent.Dsl.InterruptHook{}, &1))
      )

    guardrail_entities =
      env.module
      |> Spark.Dsl.Extension.get_entities([:guardrails])
      |> Enum.filter(
        &(match?(%Moto.Agent.Dsl.InputGuardrail{}, &1) or
            match?(%Moto.Agent.Dsl.OutputGuardrail{}, &1) or
            match?(%Moto.Agent.Dsl.ToolGuardrail{}, &1))
      )

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

    configured_subagents = resolve_subagents!(env.module, subagent_entities)

    configured_hooks =
      hook_entities
      |> Enum.reduce(Moto.Hooks.default_stage_map(), fn
        %Moto.Agent.Dsl.BeforeTurnHook{hook: hook}, acc ->
          Map.update!(acc, :before_turn, &(&1 ++ [hook]))

        %Moto.Agent.Dsl.AfterTurnHook{hook: hook}, acc ->
          Map.update!(acc, :after_turn, &(&1 ++ [hook]))

        %Moto.Agent.Dsl.InterruptHook{hook: hook}, acc ->
          Map.update!(acc, :on_interrupt, &(&1 ++ [hook]))
      end)
      |> then(&resolve_hooks!(env.module, &1))

    configured_guardrails =
      guardrail_entities
      |> Enum.reduce(Moto.Guardrails.default_stage_map(), fn
        %Moto.Agent.Dsl.InputGuardrail{guardrail: guardrail}, acc ->
          Map.update!(acc, :input, &(&1 ++ [guardrail]))

        %Moto.Agent.Dsl.OutputGuardrail{guardrail: guardrail}, acc ->
          Map.update!(acc, :output, &(&1 ++ [guardrail]))

        %Moto.Agent.Dsl.ToolGuardrail{guardrail: guardrail}, acc ->
          Map.update!(acc, :tool, &(&1 ++ [guardrail]))
      end)
      |> then(&resolve_guardrails!(env.module, &1))

    configured_context = resolve_context!(env.module, context_entities)

    memory_section_anno =
      env.module
      |> Module.get_attribute(:spark_dsl_config)
      |> case do
        %{} = dsl -> Spark.Dsl.Extension.get_section_anno(dsl, [:memory])
        _ -> nil
      end

    configured_memory =
      cond do
        memory_entities != [] ->
          resolve_memory!(env.module, memory_entities)

        not is_nil(memory_section_anno) ->
          Moto.Memory.default_config()

        true ->
          nil
      end

    direct_tool_names =
      case Moto.Tool.tool_names(direct_tool_modules) do
        {:ok, tool_names} ->
          tool_names

        {:error, message} ->
          raise Spark.Error.DslError,
            message: message,
            path: [:tools, :tool],
            module: env.module
      end

    plugin_names =
      case Moto.Plugin.plugin_names(plugin_modules) do
        {:ok, plugin_names} ->
          plugin_names

        {:error, message} ->
          raise Spark.Error.DslError,
            message: message,
            path: [:plugins, :plugin],
            module: env.module
      end

    plugin_tool_modules =
      case Moto.Plugin.plugin_actions(plugin_modules) do
        {:ok, plugin_tool_modules} ->
          plugin_tool_modules

        {:error, message} ->
          raise Spark.Error.DslError,
            message: message,
            path: [:plugins, :plugin],
            module: env.module
      end

    plugin_tool_names =
      case Moto.Tool.action_names(plugin_tool_modules) do
        {:ok, plugin_tool_names} ->
          plugin_tool_names

        {:error, message} ->
          raise Spark.Error.DslError,
            message: message,
            path: [:plugins, :plugin],
            module: env.module
      end

    subagent_tool_modules =
      configured_subagents
      |> Enum.with_index()
      |> Enum.map(fn {subagent, index} ->
        Moto.Subagent.tool_module(env.module, subagent, index)
      end)

    subagent_tool_names = Enum.map(configured_subagents, & &1.name)

    ash_resource_info =
      case Moto.Agent.AshResources.expand(ash_resources) do
        {:ok, ash_resource_info} ->
          ash_resource_info

        {:error, message} ->
          raise Spark.Error.DslError,
            message: message,
            path: [:tools, :ash_resource],
            module: env.module
      end

    runtime_plugins = Moto.Agent.Runtime.runtime_plugins(plugin_modules, configured_memory)

    tool_modules =
      direct_tool_modules ++
        ash_resource_info.tool_modules ++
        plugin_tool_modules ++
        subagent_tool_modules

    tool_names =
      direct_tool_names ++
        ash_resource_info.tool_names ++
        plugin_tool_names ++
        subagent_tool_names

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
        module: env.module
    end

    ash_tool_config =
      case ash_resource_info.resources do
        [] ->
          nil

        _ ->
          %{
            resources: ash_resource_info.resources,
            domain: ash_resource_info.domain,
            require_actor?: true
          }
      end

    runtime_module = Module.concat(env.module, Runtime)
    request_transformer_module = Module.concat(env.module, RuntimeRequestTransformer)

    if is_nil(configured_system_prompt) do
      raise CompileError,
        file: env.file,
        line: env.line,
        description: "Moto.Agent requires `system_prompt` inside `agent do ... end`."
    end

    {runtime_system_prompt, dynamic_system_prompt} =
      case resolve_system_prompt!(env.module, configured_system_prompt) do
        {:static, prompt} ->
          {prompt, nil}

        {:dynamic, spec} ->
          {nil, spec}
      end

    request_transformer_system_prompt =
      case dynamic_system_prompt do
        nil -> runtime_system_prompt
        spec -> spec
      end

    effective_request_transformer =
      if is_nil(dynamic_system_prompt) and
           not Moto.Memory.requires_request_transformer?(configured_memory) do
        nil
      else
        request_transformer_module
      end

    request_transformer_definition =
      if is_nil(effective_request_transformer) do
        quote do
        end
      else
        quote location: :keep do
          defmodule unquote(request_transformer_module) do
            @moduledoc false
            @behaviour Jido.AI.Reasoning.ReAct.RequestTransformer

            @system_prompt_spec unquote(Macro.escape(request_transformer_system_prompt))

            @impl true
            def transform_request(request, state, config, runtime_context) do
              Moto.Agent.RequestTransformer.transform_request(
                @system_prompt_spec,
                request,
                state,
                config,
                runtime_context
              )
            end
          end
        end
      end

    subagent_tool_definitions =
      configured_subagents
      |> Enum.with_index()
      |> Enum.map(fn {subagent, index} ->
        tool_module = Enum.at(subagent_tool_modules, index)
        Moto.Subagent.tool_module_ast(tool_module, subagent)
      end)

    quote location: :keep do
      unquote(request_transformer_definition)
      unquote_splicing(subagent_tool_definitions)

      defmodule unquote(runtime_module) do
        use Jido.AI.Agent,
          name: unquote(name),
          system_prompt: unquote(runtime_system_prompt),
          model: unquote(Macro.escape(resolved_model)),
          tools: unquote(Macro.escape(tool_modules)),
          plugins: unquote(Macro.escape(runtime_plugins)),
          default_plugins: %{__memory__: false},
          request_transformer: unquote(effective_request_transformer)

        unquote(
          Moto.Agent.Runtime.hook_runtime_ast(
            configured_hooks,
            configured_context,
            configured_guardrails,
            configured_memory
          )
        )
      end

      @doc """
      Starts this agent under the shared `Moto.Runtime` instance.
      """
      @spec start_link(keyword()) :: DynamicSupervisor.on_start_child()
      def start_link(opts \\ []) do
        Moto.start_agent(unquote(runtime_module), opts)
      end

      @doc """
      Convenience alias for `ask_sync/3`.
      """
      @spec chat(pid(), String.t(), keyword()) :: {:ok, term()} | {:error, term()}
      def chat(pid, message, opts \\ []) when is_pid(pid) and is_binary(message) do
        with {:ok, prepared_opts} <-
               Moto.Agent.prepare_chat_opts(
                 opts,
                 %{
                   context: unquote(Macro.escape(configured_context)),
                   ash: unquote(Macro.escape(ash_tool_config))
                 }
               ) do
          Moto.chat_request(pid, message, prepared_opts)
          |> Moto.Hooks.translate_chat_result()
        end
      end

      @doc """
      Returns the generated runtime module used internally by Moto.
      """
      @spec runtime_module() :: module()
      def runtime_module, do: unquote(runtime_module)

      @doc """
      Returns the configured public agent name.
      """
      @spec name() :: String.t()
      def name, do: unquote(name)

      @doc """
      Returns the configured system prompt.
      """
      @spec system_prompt() :: Moto.Agent.SystemPrompt.spec()
      def system_prompt, do: unquote(Macro.escape(configured_system_prompt))

      @doc """
      Returns the generated request transformer used for a dynamic system prompt, if any.
      """
      @spec request_transformer() :: module() | nil
      def request_transformer, do: unquote(effective_request_transformer)

      @doc """
      Returns the configured model before alias resolution.
      """
      @spec configured_model() :: term()
      def configured_model, do: unquote(Macro.escape(configured_model))

      @doc """
      Returns the resolved model used by the generated runtime module.
      """
      @spec model() :: term()
      def model, do: unquote(Macro.escape(resolved_model))

      @doc """
      Returns the configured default runtime context for this agent.
      """
      @spec context() :: map()
      def context, do: unquote(Macro.escape(configured_context))

      @doc """
      Returns the configured memory settings for this agent, if any.
      """
      @spec memory() :: Moto.Memory.config() | nil
      def memory, do: unquote(Macro.escape(configured_memory))

      @doc """
      Returns the configured tool modules.
      """
      @spec tools() :: [module()]
      def tools, do: unquote(Macro.escape(tool_modules))

      @doc """
      Returns the configured published tool names.
      """
      @spec tool_names() :: [String.t()]
      def tool_names, do: unquote(Macro.escape(tool_names))

      @doc """
      Returns the configured subagent definitions.
      """
      @spec subagents() :: [Moto.Subagent.t()]
      def subagents, do: unquote(Macro.escape(configured_subagents))

      @doc """
      Returns the configured published subagent names.
      """
      @spec subagent_names() :: [String.t()]
      def subagent_names, do: unquote(Macro.escape(subagent_tool_names))

      @doc """
      Returns the configured Moto plugin modules.
      """
      @spec plugins() :: [module()]
      def plugins, do: unquote(Macro.escape(plugin_modules))

      @doc """
      Returns the configured published Moto plugin names.
      """
      @spec plugin_names() :: [String.t()]
      def plugin_names, do: unquote(Macro.escape(plugin_names))

      @doc """
      Returns the configured hooks by stage.
      """
      @spec hooks() :: Moto.Hooks.stage_map()
      def hooks, do: unquote(Macro.escape(configured_hooks))

      @doc """
      Returns the configured `before_turn` hooks.
      """
      @spec before_turn_hooks() :: [term()]
      def before_turn_hooks, do: unquote(Macro.escape(configured_hooks.before_turn))

      @doc """
      Returns the configured `after_turn` hooks.
      """
      @spec after_turn_hooks() :: [term()]
      def after_turn_hooks, do: unquote(Macro.escape(configured_hooks.after_turn))

      @doc """
      Returns the configured `on_interrupt` hooks.
      """
      @spec interrupt_hooks() :: [term()]
      def interrupt_hooks, do: unquote(Macro.escape(configured_hooks.on_interrupt))

      @doc """
      Returns the configured Moto guardrails by stage.
      """
      @spec guardrails() :: Moto.Guardrails.stage_map()
      def guardrails, do: unquote(Macro.escape(configured_guardrails))

      @doc """
      Returns the configured input guardrails.
      """
      @spec input_guardrails() :: [Moto.Guardrails.guardrail_ref()]
      def input_guardrails, do: unquote(Macro.escape(configured_guardrails.input))

      @doc """
      Returns the configured output guardrails.
      """
      @spec output_guardrails() :: [Moto.Guardrails.guardrail_ref()]
      def output_guardrails, do: unquote(Macro.escape(configured_guardrails.output))

      @doc """
      Returns the configured tool guardrails.
      """
      @spec tool_guardrails() :: [Moto.Guardrails.guardrail_ref()]
      def tool_guardrails, do: unquote(Macro.escape(configured_guardrails.tool))

      @doc """
      Returns any Ash resources registered through `ash_resource`.
      """
      @spec ash_resources() :: [module()]
      def ash_resources, do: unquote(Macro.escape(ash_resource_info.resources))

      @doc """
      Returns the inferred Ash domain for `ash_resource` tools, if present.
      """
      @spec ash_domain() :: module() | nil
      def ash_domain, do: unquote(Macro.escape(ash_resource_info.domain))

      @doc """
      Returns whether this agent requires an explicit `context.actor`.
      """
      @spec requires_actor?() :: boolean()
      def requires_actor?, do: unquote(ash_resource_info.require_actor?)
    end
  end
end
