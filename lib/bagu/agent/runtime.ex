defmodule Bagu.Agent.Runtime do
  @moduledoc false

  @spec hook_runtime_ast(
          Bagu.Hooks.stage_map(),
          map(),
          Bagu.Guardrails.stage_map(),
          Bagu.Memory.config() | nil,
          Bagu.Skill.config() | nil,
          Bagu.MCP.config()
        ) :: Macro.t()
  def hook_runtime_ast(
        default_hooks,
        default_context \\ %{},
        default_guardrails \\ Bagu.Guardrails.default_stage_map(),
        default_memory \\ nil,
        default_skills \\ nil,
        default_mcp_tools \\ []
      ) do
    quote location: :keep do
      @bagu_hook_defaults unquote(Macro.escape(default_hooks))
      @bagu_context_defaults unquote(Macro.escape(default_context))
      @bagu_guardrail_defaults unquote(Macro.escape(default_guardrails))
      @bagu_memory_defaults unquote(Macro.escape(default_memory))
      @bagu_skill_defaults unquote(Macro.escape(default_skills))
      @bagu_mcp_defaults unquote(Macro.escape(default_mcp_tools))

      @impl true
      def on_before_cmd(agent, action) do
        with {:ok, agent, action} <- super(agent, action),
             {:ok, agent, action} <-
               Bagu.Memory.on_before_cmd(
                 agent,
                 action,
                 @bagu_memory_defaults,
                 @bagu_context_defaults
               ),
             {:ok, agent, action} <-
               Bagu.Hooks.on_before_cmd(
                 __MODULE__,
                 agent,
                 action,
                 @bagu_hook_defaults,
                 @bagu_context_defaults
               ),
             {:ok, agent, action} <-
               Bagu.Skill.on_before_cmd(agent, action, @bagu_skill_defaults),
             {:ok, agent, action} <-
               Bagu.Guardrails.on_before_cmd(agent, action, @bagu_guardrail_defaults),
             {:ok, agent, action} <- Bagu.MCP.on_before_cmd(agent, action, @bagu_mcp_defaults),
             {:ok, agent, action} <- Bagu.Subagent.on_before_cmd(agent, action) do
          {:ok, agent, action}
        end
      end

      @impl true
      def on_after_cmd(agent, action, directives) do
        with {:ok, agent, directives} <- super(agent, action, directives),
             {:ok, agent, directives} <-
               Bagu.Hooks.on_after_cmd(__MODULE__, agent, action, directives, @bagu_hook_defaults),
             {:ok, agent, directives} <-
               Bagu.Guardrails.on_after_cmd(agent, action, directives, @bagu_guardrail_defaults),
             {:ok, agent, directives} <-
               Bagu.Memory.on_after_cmd(agent, action, directives, @bagu_memory_defaults),
             {:ok, agent, directives} <- Bagu.Subagent.on_after_cmd(agent, action, directives),
             {:ok, agent, directives} <- Bagu.Workflow.Capability.on_after_cmd(agent, action, directives) do
          {:ok, agent, directives}
        end
      end
    end
  end

  @spec runtime_plugins([module()], Bagu.Memory.config() | nil) :: [module() | {module(), map()}]
  def runtime_plugins(plugin_modules, _memory_config), do: [Bagu.Plugins.RuntimeCompat | plugin_modules]
end
