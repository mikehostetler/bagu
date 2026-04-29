defmodule Jidoka.Agent.Dsl.Sections.Contract do
  @moduledoc false

  @spec output_section() :: Spark.Dsl.Section.t()
  def output_section do
    %Spark.Dsl.Section{
      name: :output,
      describe: """
      Configure the final structured output contract for this agent.
      """,
      schema: [
        schema: [
          type: :any,
          required: true,
          doc: "A Zoi object/map schema for the final agent response."
        ],
        retries: [
          type: :integer,
          required: false,
          default: 1,
          doc: "Number of final-output repair attempts. Values above 3 are capped."
        ],
        on_validation_error: [
          type: {:in, [:repair, :error]},
          required: false,
          default: :repair,
          doc: "Whether invalid model output should be repaired once or returned as an error."
        ]
      ]
    }
  end

  @spec agent_section() :: Spark.Dsl.Section.t()
  def agent_section do
    %Spark.Dsl.Section{
      name: :agent,
      describe: """
      Configure the immutable Jidoka agent contract.
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
      ],
      sections: [output_section()]
    }
  end

  @spec defaults_section() :: Spark.Dsl.Section.t()
  def defaults_section do
    %Spark.Dsl.Section{
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
        ],
        character: [
          type: :any,
          required: false,
          doc: """
          Optional structured character/persona source rendered before
          `instructions` in the effective system prompt.

          Supports inline `Jido.Character` maps or modules generated with
          `use Jido.Character`.
          """
        ]
      ]
    }
  end
end
