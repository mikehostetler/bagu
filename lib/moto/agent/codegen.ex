defmodule Moto.Agent.Codegen do
  @moduledoc false

  @spec emit(Moto.Agent.Definition.t()) :: Macro.t()
  def emit(definition) when is_map(definition) do
    request_transformer_definition = request_transformer_definition(definition)
    subagent_tool_definitions = subagent_tool_definitions(definition)

    quote location: :keep do
      unquote(request_transformer_definition)
      unquote_splicing(subagent_tool_definitions)

      defmodule unquote(definition.runtime_module) do
        use Jido.AI.Agent,
          name: unquote(definition.name),
          system_prompt: unquote(definition.runtime_system_prompt),
          model: unquote(Macro.escape(definition.model)),
          tools: unquote(Macro.escape(definition.tools)),
          plugins: unquote(Macro.escape(definition.runtime_plugins)),
          default_plugins: %{__memory__: false},
          request_transformer: unquote(definition.effective_request_transformer)

        unquote(
          Moto.Agent.Runtime.hook_runtime_ast(
            definition.hooks,
            definition.context,
            definition.guardrails,
            definition.memory,
            definition.skills,
            definition.mcp_tools
          )
        )

        @doc false
        @spec __moto_owner_module__() :: module()
        def __moto_owner_module__, do: unquote(definition.module)

        @doc false
        @spec __moto_definition__() :: map()
        def __moto_definition__, do: unquote(Macro.escape(definition.public_definition))
      end

      unquote(public_agent_functions(definition))
    end
  end

  defp request_transformer_definition(%{effective_request_transformer: nil}) do
    quote do
    end
  end

  defp request_transformer_definition(definition) do
    quote location: :keep do
      defmodule unquote(definition.request_transformer_module) do
        @moduledoc false
        @behaviour Jido.AI.Reasoning.ReAct.RequestTransformer

        @system_prompt_spec unquote(Macro.escape(definition.request_transformer_system_prompt))
        @skills_config unquote(Macro.escape(definition.skills))

        @impl true
        def transform_request(request, state, config, runtime_context) do
          Moto.Agent.RequestTransformer.transform_request(
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
  end

  defp subagent_tool_definitions(definition) do
    definition.subagents
    |> Enum.with_index()
    |> Enum.map(fn {subagent, index} ->
      tool_module = Enum.at(definition.subagent_tool_modules, index)
      Moto.Subagent.tool_module_ast(tool_module, subagent)
    end)
  end

  defp public_agent_functions(definition) do
    quote location: :keep do
      @doc """
      Starts this agent under the shared `Moto.Runtime` instance.
      """
      @spec start_link(keyword()) :: DynamicSupervisor.on_start_child()
      def start_link(opts \\ []) do
        Moto.start_agent(unquote(definition.runtime_module), opts)
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
                   context: unquote(Macro.escape(definition.context)),
                   context_schema: unquote(Macro.escape(definition.context_schema)),
                   ash: unquote(Macro.escape(definition.ash_tool_config))
                 }
               ) do
          Moto.chat_request(pid, message, prepared_opts)
          |> Moto.Hooks.translate_chat_result()
        end
      end

      @doc """
      Returns Moto's compiled agent-definition metadata for inspection tooling.
      """
      @spec __moto__() :: map()
      def __moto__, do: unquote(Macro.escape(definition.public_definition))

      @doc """
      Returns the generated runtime module used internally by Moto.
      """
      @spec runtime_module() :: module()
      def runtime_module, do: unquote(definition.runtime_module)

      @doc """
      Returns the configured public agent name.
      """
      @spec name() :: String.t()
      def name, do: unquote(definition.name)

      @doc """
      Returns the configured system prompt.
      """
      @spec system_prompt() :: Moto.Agent.SystemPrompt.spec()
      def system_prompt, do: unquote(Macro.escape(definition.configured_system_prompt))

      @doc """
      Returns the generated request transformer used for a dynamic system prompt, if any.
      """
      @spec request_transformer() :: module() | nil
      def request_transformer, do: unquote(definition.effective_request_transformer)

      @doc """
      Returns the configured model before alias resolution.
      """
      @spec configured_model() :: term()
      def configured_model, do: unquote(Macro.escape(definition.configured_model))

      @doc """
      Returns the resolved model used by the generated runtime module.
      """
      @spec model() :: term()
      def model, do: unquote(Macro.escape(definition.model))

      @doc """
      Returns the configured Zoi runtime context schema, if any.
      """
      @spec context_schema() :: Moto.Context.schema()
      def context_schema, do: unquote(Macro.escape(definition.context_schema))

      @doc """
      Returns the configured default runtime context for this agent.
      """
      @spec context() :: map()
      def context, do: unquote(Macro.escape(definition.context))

      @doc """
      Returns the configured memory settings for this agent, if any.
      """
      @spec memory() :: Moto.Memory.config() | nil
      def memory, do: unquote(Macro.escape(definition.memory))

      @doc """
      Returns the configured skill settings for this agent, if any.
      """
      @spec skills() :: Moto.Skill.config() | nil
      def skills, do: unquote(Macro.escape(definition.skills))

      @doc """
      Returns the configured published skill names.
      """
      @spec skill_names() :: [String.t()]
      def skill_names, do: unquote(Macro.escape(definition.skill_names))

      @doc """
      Returns the configured tool modules.
      """
      @spec tools() :: [module()]
      def tools, do: unquote(Macro.escape(definition.tools))

      @doc """
      Returns the configured published tool names.
      """
      @spec tool_names() :: [String.t()]
      def tool_names, do: unquote(Macro.escape(definition.tool_names))

      @doc """
      Returns the configured MCP tool sync settings.
      """
      @spec mcp_tools() :: Moto.MCP.config()
      def mcp_tools, do: unquote(Macro.escape(definition.mcp_tools))

      @doc """
      Returns the configured subagent definitions.
      """
      @spec subagents() :: [Moto.Subagent.t()]
      def subagents, do: unquote(Macro.escape(definition.subagents))

      @doc """
      Returns the configured published subagent names.
      """
      @spec subagent_names() :: [String.t()]
      def subagent_names, do: unquote(Macro.escape(definition.subagent_names))

      @doc """
      Returns the configured Moto plugin modules.
      """
      @spec plugins() :: [module()]
      def plugins, do: unquote(Macro.escape(definition.plugins))

      @doc """
      Returns the configured published Moto plugin names.
      """
      @spec plugin_names() :: [String.t()]
      def plugin_names, do: unquote(Macro.escape(definition.plugin_names))

      @doc """
      Returns the configured hooks by stage.
      """
      @spec hooks() :: Moto.Hooks.stage_map()
      def hooks, do: unquote(Macro.escape(definition.hooks))

      @doc """
      Returns the configured `before_turn` hooks.
      """
      @spec before_turn_hooks() :: [term()]
      def before_turn_hooks, do: unquote(Macro.escape(definition.hooks.before_turn))

      @doc """
      Returns the configured `after_turn` hooks.
      """
      @spec after_turn_hooks() :: [term()]
      def after_turn_hooks, do: unquote(Macro.escape(definition.hooks.after_turn))

      @doc """
      Returns the configured `on_interrupt` hooks.
      """
      @spec interrupt_hooks() :: [term()]
      def interrupt_hooks, do: unquote(Macro.escape(definition.hooks.on_interrupt))

      @doc """
      Returns the configured Moto guardrails by stage.
      """
      @spec guardrails() :: Moto.Guardrails.stage_map()
      def guardrails, do: unquote(Macro.escape(definition.guardrails))

      @doc """
      Returns the configured input guardrails.
      """
      @spec input_guardrails() :: [Moto.Guardrails.guardrail_ref()]
      def input_guardrails, do: unquote(Macro.escape(definition.guardrails.input))

      @doc """
      Returns the configured output guardrails.
      """
      @spec output_guardrails() :: [Moto.Guardrails.guardrail_ref()]
      def output_guardrails, do: unquote(Macro.escape(definition.guardrails.output))

      @doc """
      Returns the configured tool guardrails.
      """
      @spec tool_guardrails() :: [Moto.Guardrails.guardrail_ref()]
      def tool_guardrails, do: unquote(Macro.escape(definition.guardrails.tool))

      @doc """
      Returns any Ash resources registered through `ash_resource`.
      """
      @spec ash_resources() :: [module()]
      def ash_resources, do: unquote(Macro.escape(definition.ash_resources))

      @doc """
      Returns the inferred Ash domain for `ash_resource` tools, if present.
      """
      @spec ash_domain() :: module() | nil
      def ash_domain, do: unquote(Macro.escape(definition.ash_domain))

      @doc """
      Returns whether this agent requires an explicit `context.actor`.
      """
      @spec requires_actor?() :: boolean()
      def requires_actor?, do: unquote(definition.requires_actor?)
    end
  end
end
