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
  - `tools`
  - `plugins`
  - `hooks`

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
  def prepare_chat_opts(opts, nil) when is_list(opts) do
    with :ok <- reject_tool_context(opts),
         {:ok, opts} <- Moto.Hooks.prepare_request_opts(opts),
         {:ok, context} <- merge_default_context(opts, %{}) do
      {:ok, Keyword.put(opts, :tool_context, context)}
    end
  end

  def prepare_chat_opts(opts, config) when is_list(opts) do
    default_context = default_context(config)
    ash_tool_config = ash_tool_config(config)

    with :ok <- reject_tool_context(opts),
         {:ok, opts} <- Moto.Hooks.prepare_request_opts(opts),
         {:ok, context} <- merge_default_context(opts, default_context),
         {:ok, context} <- maybe_prepare_ash_context(context, ash_tool_config) do
      {:ok, Keyword.put(opts, :tool_context, context)}
    end
  end

  @doc false
  def hook_runtime_ast(default_hooks, default_context \\ %{}) do
    quote location: :keep do
      @moto_hook_defaults unquote(Macro.escape(default_hooks))
      @moto_context_defaults unquote(Macro.escape(default_context))

      @impl true
      def on_before_cmd(agent, action) do
        with {:ok, agent, action} <- super(agent, action) do
          Moto.Hooks.on_before_cmd(
            __MODULE__,
            agent,
            action,
            @moto_hook_defaults,
            @moto_context_defaults
          )
        end
      end

      @impl true
      def on_after_cmd(agent, action, directives) do
        with {:ok, agent, directives} <- super(agent, action, directives) do
          Moto.Hooks.on_after_cmd(__MODULE__, agent, action, directives, @moto_hook_defaults)
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

  defp normalize_context(context), do: Moto.Context.normalize(context)

  defp merge_default_context(opts, default_context) do
    with {:ok, runtime_context} <- normalize_context(Keyword.get(opts, :tool_context, %{})) do
      {:ok, Moto.Context.merge(default_context, runtime_context)}
    end
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

    hook_entities =
      env.module
      |> Spark.Dsl.Extension.get_entities([:hooks])
      |> Enum.filter(
        &(match?(%Moto.Agent.Dsl.BeforeTurnHook{}, &1) or
            match?(%Moto.Agent.Dsl.AfterTurnHook{}, &1) or
            match?(%Moto.Agent.Dsl.InterruptHook{}, &1))
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
    configured_context = __MODULE__.resolve_context!(env.module, context_entities)

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

    runtime_plugins = [Moto.Plugins.RuntimeCompat | plugin_modules]

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

    {runtime_system_prompt, runtime_request_transformer, dynamic_system_prompt} =
      case __MODULE__.resolve_system_prompt!(env.module, configured_system_prompt) do
        {:static, prompt} ->
          {prompt, nil, nil}

        {:dynamic, spec} ->
          {nil, request_transformer_module, spec}
      end

    request_transformer_definition =
      if is_nil(dynamic_system_prompt) do
        quote do
        end
      else
        quote location: :keep do
          defmodule unquote(request_transformer_module) do
            @moduledoc false
            @behaviour Jido.AI.Reasoning.ReAct.RequestTransformer

            @system_prompt_spec unquote(Macro.escape(dynamic_system_prompt))

            @impl true
            def transform_request(request, state, config, runtime_context) do
              Moto.Agent.SystemPrompt.transform_request(
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
          request_transformer: unquote(runtime_request_transformer)

        unquote(__MODULE__.hook_runtime_ast(configured_hooks, configured_context))
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
      def request_transformer, do: unquote(runtime_request_transformer)

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
