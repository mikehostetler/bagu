defmodule Moto.Examples.Chat.Agents.ChatAgent do
  use Moto.Agent

  agent do
    name("script_chat_agent")
    model(:fast)

    schema(
      Zoi.object(%{
        tenant: Zoi.string() |> Zoi.default("demo"),
        channel: Zoi.string() |> Zoi.default("cli"),
        session: Zoi.string() |> Zoi.optional(),
        notify_pid: Zoi.any() |> Zoi.optional()
      })
    )

    system_prompt("""
    You are a concise assistant.
    Keep answers short and direct.
    """)
  end

  memory do
    mode(:conversation)
    namespace({:context, :session})
    capture(:conversation)
    retrieve(limit: 4)
    inject(:system_prompt)
  end

  skills do
    skill("math-discipline")
    load_path("../skills")
  end

  plugins do
    plugin(Moto.Examples.Chat.Plugins.MathPlugin)
  end

  hooks do
    before_turn(Moto.Examples.Chat.Hooks.ReplyWithFinalAnswer)
    after_turn(Moto.Examples.Chat.Hooks.TagAfterTurn)
    after_turn(Moto.Examples.Chat.Hooks.RequireApprovalForRefunds)
    on_interrupt(Moto.Examples.Chat.Hooks.NotifyInterrupt)
  end

  guardrails do
    input(Moto.Examples.Chat.Guardrails.BlockSecretPrompt)
    output(Moto.Examples.Chat.Guardrails.BlockUnsafeReply)
    tool(Moto.Examples.Chat.Guardrails.ApproveLargeMathTool)
  end
end
