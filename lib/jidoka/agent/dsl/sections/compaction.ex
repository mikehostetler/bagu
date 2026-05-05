defmodule Jidoka.Agent.Dsl.Sections.Compaction do
  @moduledoc false

  alias Jidoka.Agent.Dsl.{
    CompactionKeepLast,
    CompactionMaxMessages,
    CompactionMaxSummaryChars,
    CompactionMode,
    CompactionPrompt,
    CompactionStrategy
  }

  @spec mode_entity() :: Spark.Dsl.Entity.t()
  def mode_entity do
    %Spark.Dsl.Entity{
      name: :mode,
      describe: """
      Configure automatic conversation compaction.
      """,
      target: CompactionMode,
      args: [:value],
      schema: [
        value: [
          type: :any,
          required: true,
          doc: "Supports :auto, :manual, or :off."
        ]
      ]
    }
  end

  @spec strategy_entity() :: Spark.Dsl.Entity.t()
  def strategy_entity do
    %Spark.Dsl.Entity{
      name: :strategy,
      describe: """
      Configure the compaction strategy.
      """,
      target: CompactionStrategy,
      args: [:value],
      schema: [
        value: [
          type: :any,
          required: true,
          doc: "Only :summary is supported in v1."
        ]
      ]
    }
  end

  @spec max_messages_entity() :: Spark.Dsl.Entity.t()
  def max_messages_entity do
    %Spark.Dsl.Entity{
      name: :max_messages,
      describe: """
      Configure the provider-facing message count that triggers compaction.
      """,
      target: CompactionMaxMessages,
      args: [:value],
      schema: [
        value: [
          type: :integer,
          required: true,
          doc: "Message count threshold before compaction runs."
        ]
      ]
    }
  end

  @spec keep_last_entity() :: Spark.Dsl.Entity.t()
  def keep_last_entity do
    %Spark.Dsl.Entity{
      name: :keep_last,
      describe: """
      Configure how many recent provider-facing messages remain raw after compaction.
      """,
      target: CompactionKeepLast,
      args: [:value],
      schema: [
        value: [
          type: :integer,
          required: true,
          doc: "Number of recent messages to retain without summarizing."
        ]
      ]
    }
  end

  @spec max_summary_chars_entity() :: Spark.Dsl.Entity.t()
  def max_summary_chars_entity do
    %Spark.Dsl.Entity{
      name: :max_summary_chars,
      describe: """
      Configure the maximum generated summary size.
      """,
      target: CompactionMaxSummaryChars,
      args: [:value],
      schema: [
        value: [
          type: :integer,
          required: true,
          doc: "Maximum number of characters retained from the generated summary."
        ]
      ]
    }
  end

  @spec prompt_entity() :: Spark.Dsl.Entity.t()
  def prompt_entity do
    %Spark.Dsl.Entity{
      name: :prompt,
      describe: """
      Override the compaction summarizer prompt.
      """,
      target: CompactionPrompt,
      args: [:value],
      schema: [
        value: [
          type: :any,
          required: true,
          doc: "A string, module implementing build_compaction_prompt/1, or MFA tuple."
        ]
      ]
    }
  end

  @spec section() :: Spark.Dsl.Section.t()
  def section do
    %Spark.Dsl.Section{
      name: :compaction,
      describe: """
      Configure context compaction for long-running conversations.
      """,
      singleton_entity_keys: [:mode, :strategy, :max_messages, :keep_last, :max_summary_chars, :prompt],
      entities: [
        mode_entity(),
        strategy_entity(),
        max_messages_entity(),
        keep_last_entity(),
        max_summary_chars_entity(),
        prompt_entity()
      ]
    }
  end
end
