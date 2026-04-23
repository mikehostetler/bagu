defmodule Bagu.Agent.Dsl do
  @moduledoc false

  alias Bagu.Agent.Dsl.{
    AfterTurnHook,
    AshResource,
    BeforeTurnHook,
    InputGuardrail,
    InterruptHook,
    MCPTools,
    MemoryCapture,
    MemoryInject,
    MemoryMode,
    MemoryNamespace,
    MemoryRetrieve,
    MemorySharedNamespace,
    OutputGuardrail,
    Plugin,
    SkillPath,
    SkillRef,
    Subagent,
    Tool,
    ToolGuardrail,
    Workflow
  }

  @agent_section %Spark.Dsl.Section{
    name: :agent,
    describe: """
    Configure the immutable Bagu agent contract.
    """,
    schema: [
      id: [
        type: :any,
        required: false,
        doc: "The stable public agent id. Must be lower snake case."
      ],
      model: [
        type: :any,
        required: false,
        doc: "Legacy placement. Use `defaults do model ... end` instead."
      ],
      system_prompt: [
        type: :any,
        required: false,
        doc: "Legacy placement. Use `defaults do instructions ... end` instead."
      ],
      description: [
        type: :string,
        required: false,
        doc: "Optional human-readable description for inspection and imported specs."
      ],
      schema: [
        type: :any,
        required: false,
        doc: """
        Optional Zoi map/object schema for runtime context passed to `chat/3`.

        Defaults declared in the schema become the agent's default context.
        """
      ]
    ]
  }

  @defaults_section %Spark.Dsl.Section{
    name: :defaults,
    describe: """
    Configure runtime defaults for this agent.
    """,
    schema: [
      model: [
        type: :any,
        required: false,
        doc: """
        The default model to use for this agent.

        Supports the same shapes Jido.AI accepts, including alias atoms, direct
        model strings, inline model maps, and `%LLMDB.Model{}` structs.
        """
      ],
      instructions: [
        type: :any,
        required: false,
        doc: """
        Default instructions used for this agent.

        Supports:

        - a static string
        - a module implementing `resolve_system_prompt/1`
        - an MFA tuple like `{MyApp.Prompts.Support, :build, ["prefix"]}`
        """
      ]
    ]
  }

  @tool_entity %Spark.Dsl.Entity{
    name: :tool,
    describe: """
    Register a Bagu tool module for this agent.
    """,
    target: Tool,
    args: [:module],
    schema: [
      module: [
        type: :atom,
        required: true,
        doc: "A module defined with `use Bagu.Tool`."
      ]
    ]
  }

  @ash_resource_entity %Spark.Dsl.Entity{
    name: :ash_resource,
    describe: """
    Register all generated AshJido actions for an Ash resource as agent tools.
    """,
    target: AshResource,
    args: [:resource],
    schema: [
      resource: [
        type: :atom,
        required: true,
        doc: "An Ash resource module extended with `AshJido`."
      ]
    ]
  }

  @mcp_tools_entity %Spark.Dsl.Entity{
    name: :mcp_tools,
    describe: """
    Register remote MCP tools from a configured or runtime endpoint.
    """,
    target: MCPTools,
    args: [],
    schema: [
      endpoint: [
        type: :any,
        required: true,
        doc: "The configured MCP endpoint id."
      ],
      prefix: [
        type: :string,
        required: false,
        doc: "Optional prefix to prepend to synced tool names."
      ],
      transport: [
        type: :any,
        required: false,
        doc: "Optional inline MCP transport definition for runtime endpoint registration."
      ],
      client_info: [
        type: :map,
        required: false,
        doc: "Optional MCP client info when registering an inline endpoint."
      ],
      protocol_version: [
        type: :string,
        required: false,
        doc: "Optional MCP protocol version for an inline endpoint."
      ],
      capabilities: [
        type: :map,
        required: false,
        doc: "Optional MCP client capabilities for an inline endpoint."
      ],
      timeouts: [
        type: :map,
        required: false,
        doc: "Optional MCP timeout settings for an inline endpoint."
      ]
    ]
  }

  @skill_ref_entity %Spark.Dsl.Entity{
    name: :skill,
    describe: """
    Register a Jido.AI skill module or runtime skill name for this agent.
    """,
    target: SkillRef,
    args: [:skill],
    schema: [
      skill: [
        type: :any,
        required: true,
        doc: "A Jido.AI skill module or runtime skill name."
      ]
    ]
  }

  @skill_path_entity %Spark.Dsl.Entity{
    name: :load_path,
    describe: """
    Load SKILL.md files from a directory or file path at runtime.
    """,
    target: SkillPath,
    args: [:path],
    schema: [
      path: [
        type: :string,
        required: true,
        doc: "A directory or SKILL.md file path."
      ]
    ]
  }

  @plugin_entity %Spark.Dsl.Entity{
    name: :plugin,
    describe: """
    Register a Bagu plugin module for this agent.
    """,
    target: Plugin,
    args: [:module],
    schema: [
      module: [
        type: :atom,
        required: true,
        doc: "A module defined with `use Bagu.Plugin`."
      ]
    ]
  }

  @subagent_entity %Spark.Dsl.Entity{
    name: :subagent,
    describe: """
    Register a Bagu subagent specialist for this agent.
    """,
    target: Subagent,
    args: [:agent],
    schema: [
      agent: [
        type: :atom,
        required: true,
        doc: "A Bagu-compatible agent module that can be delegated to."
      ],
      as: [
        type: :string,
        required: false,
        doc: "Optional published tool name override for this subagent."
      ],
      description: [
        type: :string,
        required: false,
        doc: "Optional tool description override for this subagent."
      ],
      target: [
        type: :any,
        required: false,
        default: :ephemeral,
        doc: """
        Delegation mode for this subagent. Supports :ephemeral,
        {:peer, "id"}, and {:peer, {:context, key}}.
        """
      ],
      timeout: [
        type: :any,
        required: false,
        default: 30_000,
        doc: "Child delegation timeout in milliseconds."
      ],
      forward_context: [
        type: :any,
        required: false,
        default: :public,
        doc: "Context forwarding policy: :public, :none, {:only, keys}, or {:except, keys}."
      ],
      result: [
        type: :any,
        required: false,
        default: :text,
        doc: "Parent-visible result shape: :text or :structured."
      ]
    ]
  }

  @workflow_entity %Spark.Dsl.Entity{
    name: :workflow,
    describe: """
    Register a deterministic Bagu workflow as a tool-like agent capability.
    """,
    target: Workflow,
    args: [:workflow],
    schema: [
      workflow: [
        type: :atom,
        required: true,
        doc: "A module defined with `use Bagu.Workflow`."
      ],
      as: [
        type: :any,
        required: false,
        doc: "Optional published tool name override for this workflow."
      ],
      description: [
        type: :string,
        required: false,
        doc: "Optional tool description override for this workflow."
      ],
      timeout: [
        type: :any,
        required: false,
        default: 30_000,
        doc: "Workflow execution timeout in milliseconds."
      ],
      forward_context: [
        type: :any,
        required: false,
        default: :public,
        doc: "Context forwarding policy: :public, :none, {:only, keys}, or {:except, keys}."
      ],
      result: [
        type: :any,
        required: false,
        default: :output,
        doc: "Parent-visible result shape: :output or :structured."
      ]
    ]
  }

  @capabilities_section %Spark.Dsl.Section{
    name: :capabilities,
    describe: """
    Register the tools, skills, plugins, subagents, and workflows available to this agent.
    """,
    entities: [
      @tool_entity,
      @ash_resource_entity,
      @mcp_tools_entity,
      @skill_ref_entity,
      @skill_path_entity,
      @plugin_entity,
      @subagent_entity,
      @workflow_entity
    ]
  }

  @memory_mode_entity %Spark.Dsl.Entity{
    name: :mode,
    describe: """
    Configure the Bagu memory mode.
    """,
    target: MemoryMode,
    args: [:value],
    schema: [
      value: [
        type: :any,
        required: true,
        doc: "Only :conversation is supported in v1."
      ]
    ]
  }

  @memory_namespace_entity %Spark.Dsl.Entity{
    name: :namespace,
    describe: """
    Configure the memory namespace policy.
    """,
    target: MemoryNamespace,
    args: [:value],
    schema: [
      value: [
        type: :any,
        required: true,
        doc: "Supports :per_agent, :shared, or {:context, key}."
      ]
    ]
  }

  @memory_shared_namespace_entity %Spark.Dsl.Entity{
    name: :shared_namespace,
    describe: """
    Configure the shared namespace used when namespace is :shared.
    """,
    target: MemorySharedNamespace,
    args: [:value],
    schema: [
      value: [
        type: :string,
        required: true,
        doc: "The shared namespace name."
      ]
    ]
  }

  @memory_capture_entity %Spark.Dsl.Entity{
    name: :capture,
    describe: """
    Configure conversation capture behavior for Bagu memory.
    """,
    target: MemoryCapture,
    args: [:value],
    schema: [
      value: [
        type: :any,
        required: true,
        doc: "Supports :conversation or :off."
      ]
    ]
  }

  @memory_inject_entity %Spark.Dsl.Entity{
    name: :inject,
    describe: """
    Configure how retrieved memory is projected into a turn.
    """,
    target: MemoryInject,
    args: [:value],
    schema: [
      value: [
        type: :any,
        required: true,
        doc: "Supports :instructions or :context."
      ]
    ]
  }

  @memory_retrieve_entity %Spark.Dsl.Entity{
    name: :retrieve,
    describe: """
    Configure retrieval options for Bagu memory.
    """,
    target: MemoryRetrieve,
    args: [],
    schema: [
      limit: [
        type: :integer,
        required: false,
        default: 5,
        doc: "Maximum number of recent memory records to retrieve."
      ]
    ]
  }

  @memory_section %Spark.Dsl.Section{
    name: :memory,
    describe: """
    Configure conversation memory for this agent lifecycle.
    """,
    singleton_entity_keys: [:mode, :namespace, :shared_namespace, :capture, :inject, :retrieve],
    entities: [
      @memory_mode_entity,
      @memory_namespace_entity,
      @memory_shared_namespace_entity,
      @memory_capture_entity,
      @memory_inject_entity,
      @memory_retrieve_entity
    ]
  }

  @before_turn_hook_entity %Spark.Dsl.Entity{
    name: :before_turn,
    describe: """
    Register a hook that runs before a Bagu chat turn starts.
    """,
    target: BeforeTurnHook,
    args: [:hook],
    schema: [
      hook: [
        type: :any,
        required: true,
        doc: "A Bagu.Hook module or MFA tuple."
      ]
    ]
  }

  @after_turn_hook_entity %Spark.Dsl.Entity{
    name: :after_turn,
    describe: """
    Register a hook that runs after a Bagu chat turn completes.
    """,
    target: AfterTurnHook,
    args: [:hook],
    schema: [
      hook: [
        type: :any,
        required: true,
        doc: "A Bagu.Hook module or MFA tuple."
      ]
    ]
  }

  @interrupt_hook_entity %Spark.Dsl.Entity{
    name: :on_interrupt,
    describe: """
    Register a hook that runs when a Bagu turn interrupts.
    """,
    target: InterruptHook,
    args: [:hook],
    schema: [
      hook: [
        type: :any,
        required: true,
        doc: "A Bagu.Hook module or MFA tuple."
      ]
    ]
  }

  @input_guardrail_entity %Spark.Dsl.Entity{
    name: :input_guardrail,
    describe: """
    Register a guardrail that validates the final turn input before the LLM call.
    """,
    target: InputGuardrail,
    args: [:guardrail],
    schema: [
      guardrail: [
        type: :any,
        required: true,
        doc: "A Bagu.Guardrail module or MFA tuple."
      ]
    ]
  }

  @output_guardrail_entity %Spark.Dsl.Entity{
    name: :output_guardrail,
    describe: """
    Register a guardrail that validates the final turn outcome before Bagu returns it.
    """,
    target: OutputGuardrail,
    args: [:guardrail],
    schema: [
      guardrail: [
        type: :any,
        required: true,
        doc: "A Bagu.Guardrail module or MFA tuple."
      ]
    ]
  }

  @tool_guardrail_entity %Spark.Dsl.Entity{
    name: :tool_guardrail,
    describe: """
    Register a guardrail that validates model-selected tool calls before execution.
    """,
    target: ToolGuardrail,
    args: [:guardrail],
    schema: [
      guardrail: [
        type: :any,
        required: true,
        doc: "A Bagu.Guardrail module or MFA tuple."
      ]
    ]
  }

  @legacy_input_guardrail_entity %Spark.Dsl.Entity{
    name: :input,
    describe: """
    Legacy guardrail declaration. Use lifecycle.input_guardrail instead.
    """,
    target: InputGuardrail,
    args: [:guardrail],
    schema: [
      guardrail: [
        type: :any,
        required: true,
        doc: "A Bagu.Guardrail module or MFA tuple."
      ]
    ]
  }

  @legacy_output_guardrail_entity %Spark.Dsl.Entity{
    name: :output,
    describe: """
    Legacy guardrail declaration. Use lifecycle.output_guardrail instead.
    """,
    target: OutputGuardrail,
    args: [:guardrail],
    schema: [
      guardrail: [
        type: :any,
        required: true,
        doc: "A Bagu.Guardrail module or MFA tuple."
      ]
    ]
  }

  @legacy_tool_guardrail_entity %Spark.Dsl.Entity{
    name: :tool,
    describe: """
    Legacy guardrail declaration. Use lifecycle.tool_guardrail instead.
    """,
    target: ToolGuardrail,
    args: [:guardrail],
    schema: [
      guardrail: [
        type: :any,
        required: true,
        doc: "A Bagu.Guardrail module or MFA tuple."
      ]
    ]
  }

  @lifecycle_section %Spark.Dsl.Section{
    name: :lifecycle,
    describe: """
    Configure per-turn lifecycle policies for this agent.
    """,
    entities: [
      @before_turn_hook_entity,
      @after_turn_hook_entity,
      @interrupt_hook_entity,
      @input_guardrail_entity,
      @output_guardrail_entity,
      @tool_guardrail_entity
    ],
    sections: [@memory_section]
  }

  @legacy_tools_section %Spark.Dsl.Section{
    name: :tools,
    describe: """
    Legacy tool section. Use capabilities instead.
    """,
    entities: [@tool_entity, @ash_resource_entity, @mcp_tools_entity]
  }

  @legacy_skills_section %Spark.Dsl.Section{
    name: :skills,
    describe: """
    Legacy skill section. Use capabilities instead.
    """,
    entities: [@skill_ref_entity, @skill_path_entity]
  }

  @legacy_plugins_section %Spark.Dsl.Section{
    name: :plugins,
    describe: """
    Legacy plugin section. Use capabilities instead.
    """,
    entities: [@plugin_entity]
  }

  @legacy_subagents_section %Spark.Dsl.Section{
    name: :subagents,
    describe: """
    Legacy subagent section. Use capabilities instead.
    """,
    entities: [@subagent_entity]
  }

  @legacy_hooks_section %Spark.Dsl.Section{
    name: :hooks,
    describe: """
    Legacy hook section. Use lifecycle instead.
    """,
    entities: [@before_turn_hook_entity, @after_turn_hook_entity, @interrupt_hook_entity]
  }

  @legacy_guardrails_section %Spark.Dsl.Section{
    name: :guardrails,
    describe: """
    Legacy guardrail section. Use lifecycle instead.
    """,
    entities: [
      @legacy_input_guardrail_entity,
      @legacy_output_guardrail_entity,
      @legacy_tool_guardrail_entity
    ]
  }

  use Spark.Dsl.Extension,
    sections: [
      @agent_section,
      @defaults_section,
      @capabilities_section,
      @lifecycle_section,
      @memory_section,
      @legacy_tools_section,
      @legacy_skills_section,
      @legacy_subagents_section,
      @legacy_plugins_section,
      @legacy_hooks_section,
      @legacy_guardrails_section
    ],
    verifiers: [
      Bagu.Agent.Verifiers.VerifyModel,
      Bagu.Agent.Verifiers.VerifyMemory,
      Bagu.Agent.Verifiers.VerifyTools,
      Bagu.Agent.Verifiers.VerifyAshResources,
      Bagu.Agent.Verifiers.VerifySkills,
      Bagu.Agent.Verifiers.VerifySubagents,
      Bagu.Agent.Verifiers.VerifyPlugins,
      Bagu.Agent.Verifiers.VerifyHooks,
      Bagu.Agent.Verifiers.VerifyGuardrails
    ]
end
