defmodule Jidoka.Agent.Runtime do
  @moduledoc false

  @spec hook_runtime_ast(
          Jidoka.Hooks.stage_map(),
          map(),
          Jidoka.Guardrails.stage_map(),
          Jidoka.Compaction.config() | nil,
          Jidoka.Memory.config() | nil,
          Jidoka.Output.t() | nil,
          Jidoka.Skill.config() | nil,
          Jidoka.MCP.config()
        ) :: Macro.t()
  def hook_runtime_ast(
        default_hooks,
        default_context \\ %{},
        default_guardrails \\ Jidoka.Guardrails.default_stage_map(),
        default_compaction \\ nil,
        default_memory \\ nil,
        default_output \\ nil,
        default_skills \\ nil,
        default_mcp_tools \\ []
      ) do
    quote location: :keep do
      @jidoka_hook_defaults unquote(Macro.escape(default_hooks))
      @jidoka_context_defaults unquote(Macro.escape(default_context))
      @jidoka_guardrail_defaults unquote(Macro.escape(default_guardrails))
      @jidoka_compaction_defaults unquote(Macro.escape(default_compaction))
      @jidoka_memory_defaults unquote(Macro.escape(default_memory))
      @jidoka_output_defaults unquote(Macro.escape(default_output))
      @jidoka_skill_defaults unquote(Macro.escape(default_skills))
      @jidoka_mcp_defaults unquote(Macro.escape(default_mcp_tools))

      @impl true
      def on_before_cmd(agent, action) do
        with {:ok, agent, action} <- super(agent, action),
             {:ok, agent, action} <-
               Jidoka.Compaction.on_before_cmd(
                 agent,
                 action,
                 @jidoka_compaction_defaults,
                 @jidoka_context_defaults
               ),
             {:ok, agent, action} <-
               Jidoka.Memory.on_before_cmd(
                 agent,
                 action,
                 @jidoka_memory_defaults,
                 @jidoka_context_defaults
               ),
             {:ok, agent, action} <-
               Jidoka.Hooks.on_before_cmd(
                 __MODULE__,
                 agent,
                 action,
                 @jidoka_hook_defaults,
                 @jidoka_context_defaults
               ),
             {:ok, agent, action} <-
               Jidoka.Output.on_before_cmd(agent, action, @jidoka_output_defaults),
             {:ok, agent, action} <-
               Jidoka.Skill.on_before_cmd(agent, action, @jidoka_skill_defaults),
             {:ok, agent, action} <-
               Jidoka.Guardrails.on_before_cmd(agent, action, @jidoka_guardrail_defaults),
             {:ok, agent, action} <- Jidoka.MCP.on_before_cmd(agent, action, @jidoka_mcp_defaults),
             {:ok, agent, action} <- Jidoka.Subagent.on_before_cmd(agent, action),
             {:ok, agent, action} <- Jidoka.Handoff.Capability.on_before_cmd(agent, action) do
          {:ok, agent, action}
        end
      end

      @impl true
      def on_after_cmd(agent, action, directives) do
        with {:ok, agent, directives} <- super(agent, action, directives),
             {:ok, agent, directives} <-
               Jidoka.Hooks.on_after_cmd(__MODULE__, agent, action, directives, @jidoka_hook_defaults),
             {:ok, agent, directives} <-
               Jidoka.Output.on_after_cmd(agent, action, directives, @jidoka_output_defaults),
             {:ok, agent, directives} <-
               Jidoka.Guardrails.on_after_cmd(agent, action, directives, @jidoka_guardrail_defaults),
             {:ok, agent, directives} <-
               Jidoka.Memory.on_after_cmd(agent, action, directives, @jidoka_memory_defaults),
             {:ok, agent, directives} <- Jidoka.Subagent.on_after_cmd(agent, action, directives),
             {:ok, agent, directives} <- Jidoka.Workflow.Capability.on_after_cmd(agent, action, directives),
             {:ok, agent, directives} <- Jidoka.Handoff.Capability.on_after_cmd(agent, action, directives) do
          {:ok, agent, directives}
        end
      end
    end
  end

  @spec runtime_plugins([module()], Jidoka.Memory.config() | nil) :: [module() | {module(), map()}]
  def runtime_plugins(plugin_modules, _memory_config), do: [Jidoka.Plugins.RuntimeCompat | plugin_modules]
end
