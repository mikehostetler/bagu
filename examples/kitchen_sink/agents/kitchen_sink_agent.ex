defmodule Jidoka.Examples.KitchenSink.Agents.KitchenSinkAgent do
  use Jidoka.Agent

  @context_fields %{
    tenant: Zoi.string() |> Zoi.default("demo"),
    channel: Zoi.string() |> Zoi.default("kitchen_sink"),
    session: Zoi.string() |> Zoi.optional(),
    actor: Zoi.any() |> Zoi.default(%{id: "demo-actor"}),
    notify_pid: Zoi.any() |> Zoi.optional()
  }

  agent do
    id :kitchen_sink_agent

    schema Zoi.object(@context_fields)
  end

  defaults do
    model :fast
    instructions Jidoka.Examples.KitchenSink.Prompts.DynamicPrompt
  end

  capabilities do
    skill "kitchen-guidelines"
    load_path "../skills"
    tool Jidoka.Examples.KitchenSink.Tools.AddNumbers
    ash_resource Jidoka.Examples.KitchenSink.Ash.User
    mcp_tools endpoint: :local_fs, prefix: "fs_"
    plugin Jidoka.Examples.KitchenSink.Plugins.ShowcasePlugin

    subagent Jidoka.Examples.KitchenSink.Agents.ResearchAgent,
      as: "research_agent",
      description: "Ask the research specialist for concise factual notes",
      timeout: 30_000,
      forward_context: {:only, [:tenant, :channel, :session]},
      result: :structured

    subagent Jidoka.Examples.KitchenSink.Subagents.ImportedEditorSpecialist,
      as: "editor_specialist",
      description: "Ask the imported editor specialist to polish text",
      timeout: 30_000,
      forward_context: {:except, [:notify_pid]},
      result: :text
  end

  lifecycle do
    memory do
      mode :conversation
      namespace {:context, :session}
      capture :conversation
      retrieve limit: 4
      inject :instructions
    end

    compaction do
      max_messages(40)
      keep_last(12)
      max_summary_chars(4_000)
      prompt("Summarize this kitchen-sink support conversation for future turns.")
    end

    before_turn Jidoka.Examples.KitchenSink.Hooks.ShapeTurn
    after_turn Jidoka.Examples.KitchenSink.Hooks.TagReply
    on_interrupt Jidoka.Examples.KitchenSink.Hooks.NotifyInterrupt

    input_guardrail Jidoka.Examples.KitchenSink.Guardrails.BlockClassifiedPrompt
    output_guardrail Jidoka.Examples.KitchenSink.Guardrails.BlockUnsafeReply
    tool_guardrail Jidoka.Examples.KitchenSink.Guardrails.ApproveLargeMathTool
  end
end
