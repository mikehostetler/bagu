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

  defmodule Plugin do
    @moduledoc false

    defstruct [:module, :__spark_metadata__]
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

  @tools_section %Spark.Dsl.Section{
    name: :tools,
    describe: """
    Register Moto tools for this agent.
    """,
    entities: [@tool_entity, @ash_resource_entity]
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

  use Spark.Dsl.Extension,
    sections: [@agent_section, @tools_section, @plugins_section, @hooks_section],
    verifiers: [
      Moto.Agent.Verifiers.VerifyModel,
      Moto.Agent.Verifiers.VerifyTools,
      Moto.Agent.Verifiers.VerifyAshResources,
      Moto.Agent.Verifiers.VerifyPlugins,
      Moto.Agent.Verifiers.VerifyHooks
    ]
end
