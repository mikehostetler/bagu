defmodule Moto.Agent do
  @moduledoc """
  Thin Spark-backed wrapper around `Jido.AI.Agent` for Moto.

  This first DSL is intentionally tiny:

      defmodule MyApp.ChatAgent do
        use Moto.Agent

        agent do
          name "chat_agent"
          model :fast
          system_prompt "You are a concise assistant."
        end

        tools do
          tool MyApp.Tools.AddNumbers
          ash_resource MyApp.Accounts.User
        end
      end

  Supported fields are intentionally limited:

  - `name`
  - `model`
  - `system_prompt` as a string, module callback, or MFA tuple
  - `context`
  - `memory`
  - `tools`
  - `plugins`
  - `hooks`
  - `guardrails`

  A nested runtime module is generated automatically and uses `Jido.AI.Agent`
  with the configured tool modules. The `tools` block currently supports
  explicit `Moto.Tool` modules and `ash_resource` expansion via `AshJido`.
  The `plugins` block accepts `Moto.Plugin` modules and merges their declared
  action-backed tools into the same LLM-visible tool registry.
  """

  @doc false
  def resolve_model!(owner_module, model) do
    Moto.model(model)
  rescue
    error in [ArgumentError] ->
      raise Spark.Error.DslError,
        message: Exception.message(error),
        path: [:agent, :model],
        module: owner_module
  end

  @doc false
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

  @doc false
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

  @doc false
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

  @doc false
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

  @doc false
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

  @doc false
  def prepare_chat_opts(opts, nil) when is_list(opts) do
    with :ok <- reject_tool_context(opts),
         {:ok, context} <- normalize_request_context(opts, %{}),
         {:ok, context} <- attach_runtime_extensions(opts, context) do
      {:ok, finalize_chat_opts(opts, context)}
    end
  end

  def prepare_chat_opts(opts, config) when is_list(opts) do
    default_context = default_context(config)
    ash_tool_config = ash_tool_config(config)

    with :ok <- reject_tool_context(opts),
         {:ok, context} <- normalize_request_context(opts, default_context),
         {:ok, context} <- attach_runtime_extensions(opts, context),
         {:ok, context} <- maybe_prepare_ash_context(context, ash_tool_config) do
      {:ok, finalize_chat_opts(opts, context)}
    end
  end

  @doc false
  def hook_runtime_ast(
        default_hooks,
        default_context \\ %{},
        default_guardrails \\ Moto.Guardrails.default_stage_map(),
        default_memory \\ nil
      ) do
    quote location: :keep do
      @moto_hook_defaults unquote(Macro.escape(default_hooks))
      @moto_context_defaults unquote(Macro.escape(default_context))
      @moto_guardrail_defaults unquote(Macro.escape(default_guardrails))
      @moto_memory_defaults unquote(Macro.escape(default_memory))

      @impl true
      def on_before_cmd(agent, action) do
        with {:ok, agent, action} <- super(agent, action),
             {:ok, agent, action} <-
               Moto.Memory.on_before_cmd(
                 agent,
                 action,
                 @moto_memory_defaults,
                 @moto_context_defaults
               ),
             {:ok, agent, action} <-
               Moto.Hooks.on_before_cmd(
                 __MODULE__,
                 agent,
                 action,
                 @moto_hook_defaults,
                 @moto_context_defaults
               ),
             {:ok, agent, action} <-
               Moto.Guardrails.on_before_cmd(agent, action, @moto_guardrail_defaults) do
          {:ok, agent, action}
        end
      end

      @impl true
      def on_after_cmd(agent, action, directives) do
        with {:ok, agent, directives} <- super(agent, action, directives),
             {:ok, agent, directives} <-
               Moto.Hooks.on_after_cmd(__MODULE__, agent, action, directives, @moto_hook_defaults),
             {:ok, agent, directives} <-
               Moto.Guardrails.on_after_cmd(agent, action, directives, @moto_guardrail_defaults),
             {:ok, agent, directives} <-
               Moto.Memory.on_after_cmd(agent, action, directives, @moto_memory_defaults) do
          {:ok, agent, directives}
        end
      end
    end
  end

  defp reject_tool_context(opts) do
    if Keyword.has_key?(opts, :tool_context) do
      {:error, {:invalid_option, :tool_context, :use_context}}
    else
      :ok
    end
  end

  defp normalize_request_context(opts, default_context) do
    with {:ok, runtime_context} <- Moto.Context.normalize(Keyword.get(opts, :context, %{})) do
      {:ok, Moto.Context.merge(default_context, runtime_context)}
    end
  end

  defp attach_runtime_extensions(opts, context) do
    with {:ok, hooks} <- Moto.Hooks.normalize_request_hooks(Keyword.get(opts, :hooks, nil)),
         {:ok, guardrails} <-
           Moto.Guardrails.normalize_request_guardrails(Keyword.get(opts, :guardrails, nil)) do
      {:ok,
       context
       |> Moto.Hooks.attach_request_hooks(hooks)
       |> Moto.Guardrails.attach_request_guardrails(guardrails)}
    end
  end

  defp finalize_chat_opts(opts, context) do
    opts
    |> Keyword.drop([:context, :hooks, :guardrails])
    |> Keyword.put(:tool_context, context)
  end

  defp maybe_prepare_ash_context(context, nil), do: {:ok, context}

  defp maybe_prepare_ash_context(context, %{domain: domain, require_actor?: true}) do
    with :ok <- ensure_actor(context),
         {:ok, context} <- ensure_domain(context, domain) do
      {:ok, context}
    end
  end

  defp default_context(%{context: context}) when is_map(context), do: context
  defp default_context(_config), do: %{}

  defp ash_tool_config(%{ash: ash}) when is_map(ash), do: ash
  defp ash_tool_config(%{domain: _domain, require_actor?: _require_actor?} = ash), do: ash
  defp ash_tool_config(_config), do: nil

  defp ensure_actor(context) do
    case Map.get(context, :actor, Map.get(context, "actor")) do
      nil -> {:error, {:missing_context, :actor}}
      _actor -> :ok
    end
  end

  defp ensure_domain(context, domain) do
    case Map.get(context, :domain, Map.get(context, "domain")) do
      nil ->
        {:ok, Map.put(context, :domain, domain)}

      ^domain ->
        {:ok, Map.put(context, :domain, domain)}

      other ->
        {:error, {:invalid_context, {:domain_mismatch, domain, other}}}
    end
  end

  defmacro __using__(opts \\ []) do
    if opts != [] do
      raise CompileError,
        file: __CALLER__.file,
        line: __CALLER__.line,
        description:
          "Moto.Agent now uses a Spark DSL. Use `use Moto.Agent` and configure it inside `agent do ... end`."
    end

    quote location: :keep do
      use Moto.Agent.SparkDsl

      @before_compile Moto.Agent
    end
  end

  defmacro __before_compile__(env) do
    default_name =
      env.module
      |> Module.split()
      |> List.last()
      |> Macro.underscore()

    name = Spark.Dsl.Extension.get_opt(env.module, [:agent], :name, default_name)
    configured_model = Spark.Dsl.Extension.get_opt(env.module, [:agent], :model, :fast)
    resolved_model = __MODULE__.resolve_model!(env.module, configured_model)
    configured_system_prompt = Spark.Dsl.Extension.get_opt(env.module, [:agent], :system_prompt)

    tool_entities =
      env.module
      |> Spark.Dsl.Extension.get_entities([:tools])

    plugin_entities =
      env.module
      |> Spark.Dsl.Extension.get_entities([:plugins])

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

    configured_hooks = __MODULE__.resolve_hooks!(env.module, configured_hooks)

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

    configured_guardrails = __MODULE__.resolve_guardrails!(env.module, configured_guardrails)
    configured_context = __MODULE__.resolve_context!(env.module, context_entities)

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
          __MODULE__.resolve_memory!(env.module, memory_entities)

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

    runtime_plugins =
      [Moto.Plugins.RuntimeCompat | plugin_modules]
      |> maybe_add_memory_plugin(configured_memory)

    tool_modules =
      direct_tool_modules ++ ash_resource_info.tool_modules ++ plugin_tool_modules

    tool_names =
      direct_tool_names ++ ash_resource_info.tool_names ++ plugin_tool_names

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
      case __MODULE__.resolve_system_prompt!(env.module, configured_system_prompt) do
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

    quote location: :keep do
      unquote(request_transformer_definition)

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
          __MODULE__.hook_runtime_ast(
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

  defp maybe_add_memory_plugin(runtime_plugins, nil), do: runtime_plugins

  defp maybe_add_memory_plugin(runtime_plugins, memory_config) do
    runtime_plugins ++ [Moto.Memory.runtime_plugin(memory_config)]
  end
end
