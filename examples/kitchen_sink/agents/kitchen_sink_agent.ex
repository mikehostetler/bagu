defmodule Moto.Examples.KitchenSink.Agents.KitchenSinkAgent do
  use Moto.Agent

  agent do
    name("kitchen_sink_agent")
    model(:fast)

    schema(
      Zoi.object(%{
        tenant: Zoi.string() |> Zoi.default("demo"),
        channel: Zoi.string() |> Zoi.default("kitchen_sink"),
        session: Zoi.string() |> Zoi.optional(),
        actor: Zoi.any() |> Zoi.default(%{id: "demo-actor"}),
        notify_pid: Zoi.any() |> Zoi.optional()
      })
    )

    system_prompt(Moto.Examples.KitchenSink.Prompts.DynamicPrompt)
  end

  memory do
    mode(:conversation)
    namespace({:context, :session})
    capture(:conversation)
    retrieve(limit: 4)
    inject(:system_prompt)
  end

  skills do
    skill("kitchen-guidelines")
    load_path("../skills")
  end

  tools do
    tool(Moto.Examples.KitchenSink.Tools.AddNumbers)
    ash_resource(Moto.Demo.KitchenSinkAsh.User)
    mcp_tools(endpoint: :local_fs, prefix: "fs_")
  end

  plugins do
    plugin(Moto.Examples.KitchenSink.Plugins.ShowcasePlugin)
  end

  hooks do
    before_turn(Moto.Examples.KitchenSink.Hooks.ShapeTurn)
    after_turn(Moto.Examples.KitchenSink.Hooks.TagReply)
    on_interrupt(Moto.Examples.KitchenSink.Hooks.NotifyInterrupt)
  end

  guardrails do
    input(Moto.Examples.KitchenSink.Guardrails.BlockClassifiedPrompt)
    output(Moto.Examples.KitchenSink.Guardrails.BlockUnsafeReply)
    tool(Moto.Examples.KitchenSink.Guardrails.ApproveLargeMathTool)
  end

  subagents do
    subagent(Moto.Examples.KitchenSink.Agents.ResearchAgent,
      as: "research_agent",
      description: "Ask the research specialist for concise factual notes",
      timeout: 30_000,
      forward_context: {:only, [:tenant, :channel, :session]},
      result: :structured
    )

    subagent(Moto.Examples.KitchenSink.Subagents.ImportedEditorSpecialist,
      as: "editor_specialist",
      description: "Ask the imported editor specialist to polish text",
      timeout: 30_000,
      forward_context: {:except, [:notify_pid]},
      result: :text
    )
  end
end
