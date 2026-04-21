defmodule Moto.Examples.Chat.Agents.ChatAgent do
  use Moto.Agent

  agent do
    name "script_chat_agent"
    model :fast

    system_prompt """
    You are a concise assistant.
    Keep answers short and direct.
    """
  end

  context do
    put :tenant, "demo"
    put :channel, "cli"
  end

  memory do
    mode :conversation
    namespace {:context, :session}
    capture :conversation
    retrieve limit: 4
    inject :system_prompt
  end

  skills do
    skill "math-discipline"
    load_path "../skills"
  end

  plugins do
    plugin Moto.Examples.Chat.Plugins.MathPlugin
  end

  hooks do
    before_turn Moto.Examples.Chat.Hooks.ReplyWithFinalAnswer
    after_turn Moto.Examples.Chat.Hooks.TagAfterTurn
    after_turn Moto.Examples.Chat.Hooks.RequireApprovalForRefunds
    on_interrupt Moto.Examples.Chat.Hooks.NotifyInterrupt
  end

  guardrails do
    input Moto.Examples.Chat.Guardrails.BlockSecretPrompt
    output Moto.Examples.Chat.Guardrails.BlockUnsafeReply
    tool Moto.Examples.Chat.Guardrails.ApproveLargeMathTool
  end
end
