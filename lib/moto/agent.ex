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
  - `system_prompt`
  - `tools`

  A nested runtime module is generated automatically and uses `Jido.AI.Agent`
  with the configured tool modules. The `tools` block currently supports
  explicit `Moto.Tool` modules and `ash_resource` expansion via `AshJido`.
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
  def prepare_chat_opts(opts, nil) when is_list(opts), do: {:ok, opts}

  def prepare_chat_opts(opts, %{domain: domain, require_actor?: true}) when is_list(opts) do
    with {:ok, tool_context} <- normalize_tool_context(Keyword.get(opts, :tool_context, %{})),
         :ok <- ensure_actor(tool_context),
         {:ok, tool_context} <- ensure_domain(tool_context, domain) do
      {:ok, Keyword.put(opts, :tool_context, tool_context)}
    end
  end

  defp normalize_tool_context(tool_context) when is_map(tool_context), do: {:ok, tool_context}

  defp normalize_tool_context(tool_context) when is_list(tool_context),
    do: {:ok, Map.new(tool_context)}

  defp normalize_tool_context(_tool_context),
    do: {:error, {:invalid_tool_context, :expected_map}}

  defp ensure_actor(tool_context) do
    case Map.get(tool_context, :actor, Map.get(tool_context, "actor")) do
      nil -> {:error, {:missing_tool_context, :actor}}
      _actor -> :ok
    end
  end

  defp ensure_domain(tool_context, domain) do
    case Map.get(tool_context, :domain, Map.get(tool_context, "domain")) do
      nil ->
        {:ok, Map.put(tool_context, :domain, domain)}

      ^domain ->
        {:ok, Map.put(tool_context, :domain, domain)}

      other ->
        {:error, {:invalid_tool_context, {:domain_mismatch, domain, other}}}
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
    system_prompt = Spark.Dsl.Extension.get_opt(env.module, [:agent], :system_prompt)

    tool_entities =
      env.module
      |> Spark.Dsl.Extension.get_entities([:tools])

    direct_tool_modules =
      tool_entities
      |> Enum.filter(&match?(%Moto.Agent.Dsl.Tool{}, &1))
      |> Enum.map(& &1.module)

    ash_resources =
      tool_entities
      |> Enum.filter(&match?(%Moto.Agent.Dsl.AshResource{}, &1))
      |> Enum.map(& &1.resource)

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

    tool_modules = direct_tool_modules ++ ash_resource_info.tool_modules
    tool_names = direct_tool_names ++ ash_resource_info.tool_names

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

    if is_nil(system_prompt) do
      raise CompileError,
        file: env.file,
        line: env.line,
        description: "Moto.Agent requires `system_prompt` inside `agent do ... end`."
    end

    quote location: :keep do
      defmodule unquote(runtime_module) do
        use Jido.AI.Agent,
          name: unquote(name),
          system_prompt: unquote(system_prompt),
          model: unquote(Macro.escape(resolved_model)),
          tools: unquote(Macro.escape(tool_modules))
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
               Moto.Agent.prepare_chat_opts(opts, unquote(Macro.escape(ash_tool_config))) do
          unquote(runtime_module).ask_sync(pid, message, prepared_opts)
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
      @spec system_prompt() :: String.t()
      def system_prompt, do: unquote(system_prompt)

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
      Returns whether this agent requires an explicit `tool_context.actor`.
      """
      @spec requires_actor?() :: boolean()
      def requires_actor?, do: unquote(ash_resource_info.require_actor?)
    end
  end
end
