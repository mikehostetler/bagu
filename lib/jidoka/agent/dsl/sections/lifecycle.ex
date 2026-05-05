defmodule Jidoka.Agent.Dsl.Sections.Lifecycle do
  @moduledoc false

  alias Jidoka.Agent.Dsl.{
    AfterTurnHook,
    BeforeTurnHook,
    InputGuardrail,
    InterruptHook,
    OutputGuardrail,
    ToolGuardrail
  }

  alias Jidoka.Agent.Dsl.Sections.{Compaction, Memory}

  @spec before_turn_hook_entity() :: Spark.Dsl.Entity.t()
  def before_turn_hook_entity do
    %Spark.Dsl.Entity{
      name: :before_turn,
      describe: """
      Register a hook that runs before a Jidoka chat turn starts.
      """,
      target: BeforeTurnHook,
      args: [:hook],
      schema: [
        hook: [
          type: :any,
          required: true,
          doc: "A Jidoka.Hook module or MFA tuple."
        ]
      ]
    }
  end

  @spec after_turn_hook_entity() :: Spark.Dsl.Entity.t()
  def after_turn_hook_entity do
    %Spark.Dsl.Entity{
      name: :after_turn,
      describe: """
      Register a hook that runs after a Jidoka chat turn completes.
      """,
      target: AfterTurnHook,
      args: [:hook],
      schema: [
        hook: [
          type: :any,
          required: true,
          doc: "A Jidoka.Hook module or MFA tuple."
        ]
      ]
    }
  end

  @spec interrupt_hook_entity() :: Spark.Dsl.Entity.t()
  def interrupt_hook_entity do
    %Spark.Dsl.Entity{
      name: :on_interrupt,
      describe: """
      Register a hook that runs when a Jidoka turn interrupts.
      """,
      target: InterruptHook,
      args: [:hook],
      schema: [
        hook: [
          type: :any,
          required: true,
          doc: "A Jidoka.Hook module or MFA tuple."
        ]
      ]
    }
  end

  @spec input_guardrail_entity() :: Spark.Dsl.Entity.t()
  def input_guardrail_entity do
    %Spark.Dsl.Entity{
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
          doc: "A Jidoka.Guardrail module or MFA tuple."
        ]
      ]
    }
  end

  @spec output_guardrail_entity() :: Spark.Dsl.Entity.t()
  def output_guardrail_entity do
    %Spark.Dsl.Entity{
      name: :output_guardrail,
      describe: """
      Register a guardrail that validates the final turn outcome before Jidoka returns it.
      """,
      target: OutputGuardrail,
      args: [:guardrail],
      schema: [
        guardrail: [
          type: :any,
          required: true,
          doc: "A Jidoka.Guardrail module or MFA tuple."
        ]
      ]
    }
  end

  @spec tool_guardrail_entity() :: Spark.Dsl.Entity.t()
  def tool_guardrail_entity do
    %Spark.Dsl.Entity{
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
          doc: "A Jidoka.Guardrail module or MFA tuple."
        ]
      ]
    }
  end

  @spec legacy_input_guardrail_entity() :: Spark.Dsl.Entity.t()
  def legacy_input_guardrail_entity do
    %Spark.Dsl.Entity{
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
          doc: "A Jidoka.Guardrail module or MFA tuple."
        ]
      ]
    }
  end

  @spec legacy_output_guardrail_entity() :: Spark.Dsl.Entity.t()
  def legacy_output_guardrail_entity do
    %Spark.Dsl.Entity{
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
          doc: "A Jidoka.Guardrail module or MFA tuple."
        ]
      ]
    }
  end

  @spec legacy_tool_guardrail_entity() :: Spark.Dsl.Entity.t()
  def legacy_tool_guardrail_entity do
    %Spark.Dsl.Entity{
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
          doc: "A Jidoka.Guardrail module or MFA tuple."
        ]
      ]
    }
  end

  @spec section() :: Spark.Dsl.Section.t()
  def section do
    %Spark.Dsl.Section{
      name: :lifecycle,
      describe: """
      Configure per-turn lifecycle policies for this agent.
      """,
      entities: [
        before_turn_hook_entity(),
        after_turn_hook_entity(),
        interrupt_hook_entity(),
        input_guardrail_entity(),
        output_guardrail_entity(),
        tool_guardrail_entity()
      ],
      sections: [Memory.section(), Compaction.section()]
    }
  end
end
