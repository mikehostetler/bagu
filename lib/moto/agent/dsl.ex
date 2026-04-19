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
        type: :string,
        required: true,
        doc: "The system prompt used for the generated Jido.AI runtime module."
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

  use Spark.Dsl.Extension,
    sections: [@agent_section, @tools_section, @plugins_section],
    verifiers: [
      Moto.Agent.Verifiers.VerifyModel,
      Moto.Agent.Verifiers.VerifyTools,
      Moto.Agent.Verifiers.VerifyAshResources,
      Moto.Agent.Verifiers.VerifyPlugins
    ]
end
