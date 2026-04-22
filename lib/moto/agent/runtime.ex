defmodule Moto.Agent.Runtime do
  @moduledoc false

  @spec hook_runtime_ast(
          Moto.Hooks.stage_map(),
          map(),
          Moto.Guardrails.stage_map(),
          Moto.Memory.config() | nil,
          Moto.Skill.config() | nil,
          Moto.MCP.config()
        ) :: Macro.t()
  def hook_runtime_ast(
        default_hooks,
        default_context \\ %{},
        default_guardrails \\ Moto.Guardrails.default_stage_map(),
        default_memory \\ nil,
        default_skills \\ nil,
        default_mcp_tools \\ []
      ) do
    quote location: :keep do
      @moto_hook_defaults unquote(Macro.escape(default_hooks))
      @moto_context_defaults unquote(Macro.escape(default_context))
      @moto_guardrail_defaults unquote(Macro.escape(default_guardrails))
      @moto_memory_defaults unquote(Macro.escape(default_memory))
      @moto_skill_defaults unquote(Macro.escape(default_skills))
      @moto_mcp_defaults unquote(Macro.escape(default_mcp_tools))

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
               Moto.Skill.on_before_cmd(agent, action, @moto_skill_defaults),
             {:ok, agent, action} <-
               Moto.Guardrails.on_before_cmd(agent, action, @moto_guardrail_defaults),
             {:ok, agent, action} <- Moto.MCP.on_before_cmd(agent, action, @moto_mcp_defaults),
             {:ok, agent, action} <- Moto.Subagent.on_before_cmd(agent, action) do
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
               Moto.Memory.on_after_cmd(agent, action, directives, @moto_memory_defaults),
             {:ok, agent, directives} <- Moto.Subagent.on_after_cmd(agent, action, directives) do
          {:ok, agent, directives}
        end
      end
    end
  end

  @spec runtime_plugins([module()], Moto.Memory.config() | nil) :: [module() | {module(), map()}]
  def runtime_plugins(plugin_modules, _memory_config), do: [Moto.Plugins.RuntimeCompat | plugin_modules]
end
