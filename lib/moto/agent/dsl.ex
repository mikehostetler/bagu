defmodule Moto.Agent.Dsl do
  @moduledoc false

  defmodule Tool do
    @moduledoc false

    defstruct [:module, :__spark_metadata__]
  end

  defmodule AshResource do
    @moduledoc false

    defstruct [:resource, :__spark_metadata__]
  end

  defmodule MCPTools do
    @moduledoc false

    defstruct [:endpoint, :prefix, :__spark_metadata__]
  end

  defmodule Plugin do
    @moduledoc false

    defstruct [:module, :__spark_metadata__]
  end

  defmodule SkillRef do
    @moduledoc false

    defstruct [:skill, :__spark_metadata__]
  end

  defmodule SkillPath do
    @moduledoc false

    defstruct [:path, :__spark_metadata__]
  end

  defmodule Subagent do
    @moduledoc false

    defstruct [
      :agent,
      :as,
      :description,
      :target,
      :timeout,
      :forward_context,
      :result,
      :__spark_metadata__
    ]
  end

  defmodule MemoryMode do
    @moduledoc false

    defstruct [:value, :__spark_metadata__]
  end

  defmodule MemoryNamespace do
    @moduledoc false

    defstruct [:value, :__spark_metadata__]
  end

  defmodule MemorySharedNamespace do
    @moduledoc false

    defstruct [:value, :__spark_metadata__]
  end

  defmodule MemoryCapture do
    @moduledoc false

    defstruct [:value, :__spark_metadata__]
  end

  defmodule MemoryInject do
    @moduledoc false

    defstruct [:value, :__spark_metadata__]
  end

  defmodule MemoryRetrieve do
    @moduledoc false

    defstruct [:limit, :__spark_metadata__]
  end

  defmodule BeforeTurnHook do
    @moduledoc false

    defstruct [:hook, :__spark_metadata__]
  end

  defmodule AfterTurnHook do
    @moduledoc false

    defstruct [:hook, :__spark_metadata__]
  end

  defmodule InterruptHook do
    @moduledoc false

    defstruct [:hook, :__spark_metadata__]
  end

  defmodule InputGuardrail do
    @moduledoc false

    defstruct [:guardrail, :__spark_metadata__]
  end

  defmodule OutputGuardrail do
    @moduledoc false

    defstruct [:guardrail, :__spark_metadata__]
  end

  defmodule ToolGuardrail do
    @moduledoc false

    defstruct [:guardrail, :__spark_metadata__]
  end

  @agent_section %Spark.Dsl.Section{
    name: :agent,
    describe: """
    Configure the Moto agent.
    """,
    schema: [
      name: [
        type: :string,
        required: false,
        doc: "The public agent name. Defaults to the underscored module name."
      ],
      model: [
        type: :any,
        required: false,
        doc: """
        The model to use for this agent.

        Supports the same shapes Jido.AI accepts, including alias atoms, direct
        model strings, inline model maps, and `%LLMDB.Model{}` structs.
        """
      ],
      system_prompt: [
        type: :any,
        required: true,
        doc: """
        The system prompt used for this agent.

        Supports:

        - a static string
        - a module implementing `resolve_system_prompt/1`
        - an MFA tuple like `{MyApp.Prompts.Support, :build, ["prefix"]}`
        """
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

  @tool_entity %Spark.Dsl.Entity{
    name: :tool,
    describe: """
    Register a Moto tool module for this agent.
    """,
    target: Tool,
    args: [:module],
    schema: [
      module: [
        type: :atom,
        required: true,
        doc: "A module defined with `use Moto.Tool`."
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
    Register remote MCP tools from a configured endpoint.
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
      ]
    ]
  }

  @tools_section %Spark.Dsl.Section{
    name: :tools,
    describe: """
    Register Moto tools for this agent.
    """,
    entities: [@tool_entity, @ash_resource_entity, @mcp_tools_entity]
  }

  @plugin_entity %Spark.Dsl.Entity{
    name: :plugin,
    describe: """
    Register a Moto plugin module for this agent.
    """,
    target: Plugin,
    args: [:module],
    schema: [
      module: [
        type: :atom,
        required: true,
        doc: "A module defined with `use Moto.Plugin`."
      ]
    ]
  }

  @plugins_section %Spark.Dsl.Section{
    name: :plugins,
    describe: """
    Register Moto plugins for this agent.
    """,
    entities: [@plugin_entity]
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

  @skills_section %Spark.Dsl.Section{
    name: :skills,
    describe: """
    Register Jido.AI skills for this agent.
    """,
    entities: [@skill_ref_entity, @skill_path_entity]
  }

  @subagent_entity %Spark.Dsl.Entity{
    name: :subagent,
    describe: """
    Register a Moto subagent specialist for this agent.
    """,
    target: Subagent,
    args: [:agent],
    schema: [
      agent: [
        type: :atom,
        required: true,
        doc: "A Moto-compatible agent module that can be delegated to."
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

  @subagents_section %Spark.Dsl.Section{
    name: :subagents,
    describe: """
    Register subagent specialists for this agent.
    """,
    entities: [@subagent_entity]
  }

  @memory_mode_entity %Spark.Dsl.Entity{
    name: :mode,
    describe: """
    Configure the Moto memory mode.
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
    Configure conversation capture behavior for Moto memory.
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
        doc: "Supports :system_prompt or :context."
      ]
    ]
  }

  @memory_retrieve_entity %Spark.Dsl.Entity{
    name: :retrieve,
    describe: """
    Configure retrieval options for Moto memory.
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
    Configure conversation memory for this agent.
    """,
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
    Register a hook that runs before a Moto chat turn starts.
    """,
    target: BeforeTurnHook,
    args: [:hook],
    schema: [
      hook: [
        type: :any,
        required: true,
        doc: "A Moto.Hook module or MFA tuple."
      ]
    ]
  }

  @after_turn_hook_entity %Spark.Dsl.Entity{
    name: :after_turn,
    describe: """
    Register a hook that runs after a Moto chat turn completes.
    """,
    target: AfterTurnHook,
    args: [:hook],
    schema: [
      hook: [
        type: :any,
        required: true,
        doc: "A Moto.Hook module or MFA tuple."
      ]
    ]
  }

  @interrupt_hook_entity %Spark.Dsl.Entity{
    name: :on_interrupt,
    describe: """
    Register a hook that runs when a Moto turn interrupts.
    """,
    target: InterruptHook,
    args: [:hook],
    schema: [
      hook: [
        type: :any,
        required: true,
        doc: "A Moto.Hook module or MFA tuple."
      ]
    ]
  }

  @hooks_section %Spark.Dsl.Section{
    name: :hooks,
    describe: """
    Register Moto hooks for this agent.
    """,
    entities: [@before_turn_hook_entity, @after_turn_hook_entity, @interrupt_hook_entity]
  }

  @input_guardrail_entity %Spark.Dsl.Entity{
    name: :input,
    describe: """
    Register a guardrail that validates the final turn input before the LLM call.
    """,
    target: InputGuardrail,
    args: [:guardrail],
    schema: [
      guardrail: [
        type: :any,
        required: true,
        doc: "A Moto.Guardrail module or MFA tuple."
      ]
    ]
  }

  @output_guardrail_entity %Spark.Dsl.Entity{
    name: :output,
    describe: """
    Register a guardrail that validates the final turn outcome before Moto returns it.
    """,
    target: OutputGuardrail,
    args: [:guardrail],
    schema: [
      guardrail: [
        type: :any,
        required: true,
        doc: "A Moto.Guardrail module or MFA tuple."
      ]
    ]
  }

  @tool_guardrail_entity %Spark.Dsl.Entity{
    name: :tool,
    describe: """
    Register a guardrail that validates model-selected tool calls before execution.
    """,
    target: ToolGuardrail,
    args: [:guardrail],
    schema: [
      guardrail: [
        type: :any,
        required: true,
        doc: "A Moto.Guardrail module or MFA tuple."
      ]
    ]
  }

  @guardrails_section %Spark.Dsl.Section{
    name: :guardrails,
    describe: """
    Register Moto guardrails for this agent.
    """,
    entities: [@input_guardrail_entity, @output_guardrail_entity, @tool_guardrail_entity]
  }

  use Spark.Dsl.Extension,
    sections: [
      @agent_section,
      @memory_section,
      @tools_section,
      @skills_section,
      @subagents_section,
      @plugins_section,
      @hooks_section,
      @guardrails_section
    ],
    verifiers: [
      Moto.Agent.Verifiers.VerifyModel,
      Moto.Agent.Verifiers.VerifyMemory,
      Moto.Agent.Verifiers.VerifyTools,
      Moto.Agent.Verifiers.VerifyAshResources,
      Moto.Agent.Verifiers.VerifySkills,
      Moto.Agent.Verifiers.VerifySubagents,
      Moto.Agent.Verifiers.VerifyPlugins,
      Moto.Agent.Verifiers.VerifyHooks,
      Moto.Agent.Verifiers.VerifyGuardrails
    ]
end
