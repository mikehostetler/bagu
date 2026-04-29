defmodule Jidoka.Agent.Dsl.Sections.Memory do
  @moduledoc false

  alias Jidoka.Agent.Dsl.{
    MemoryCapture,
    MemoryInject,
    MemoryMode,
    MemoryNamespace,
    MemoryRetrieve,
    MemorySharedNamespace
  }

  @spec mode_entity() :: Spark.Dsl.Entity.t()
  def mode_entity do
    %Spark.Dsl.Entity{
      name: :mode,
      describe: """
      Configure the Jidoka memory mode.
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
  end

  @spec namespace_entity() :: Spark.Dsl.Entity.t()
  def namespace_entity do
    %Spark.Dsl.Entity{
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
  end

  @spec shared_namespace_entity() :: Spark.Dsl.Entity.t()
  def shared_namespace_entity do
    %Spark.Dsl.Entity{
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
  end

  @spec capture_entity() :: Spark.Dsl.Entity.t()
  def capture_entity do
    %Spark.Dsl.Entity{
      name: :capture,
      describe: """
      Configure conversation capture behavior for Jidoka memory.
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
  end

  @spec inject_entity() :: Spark.Dsl.Entity.t()
  def inject_entity do
    %Spark.Dsl.Entity{
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
  end

  @spec retrieve_entity() :: Spark.Dsl.Entity.t()
  def retrieve_entity do
    %Spark.Dsl.Entity{
      name: :retrieve,
      describe: """
      Configure retrieval options for Jidoka memory.
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
  end

  @spec section() :: Spark.Dsl.Section.t()
  def section do
    %Spark.Dsl.Section{
      name: :memory,
      describe: """
      Configure conversation memory for this agent lifecycle.
      """,
      singleton_entity_keys: [:mode, :namespace, :shared_namespace, :capture, :inject, :retrieve],
      entities: [
        mode_entity(),
        namespace_entity(),
        shared_namespace_entity(),
        capture_entity(),
        inject_entity(),
        retrieve_entity()
      ]
    }
  end
end
