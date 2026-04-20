defmodule Moto.Scripts.Demo.Agents.ChatAgent do
  use Moto.Agent

  agent do
    name "script_chat_agent"
    model :fast

    system_prompt """
    You are a concise assistant.
    Keep answers short and direct.
    For any addition or arithmetic request, you must use the add_numbers tool.
    Do not do arithmetic in your head when that tool applies.
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

  plugins do
    plugin Moto.Scripts.Demo.Plugins.MathPlugin
  end

  hooks do
    before_turn Moto.Scripts.Demo.Hooks.ReplyWithFinalAnswer
    after_turn Moto.Scripts.Demo.Hooks.TagAfterTurn
    after_turn Moto.Scripts.Demo.Hooks.RequireApprovalForRefunds
    on_interrupt Moto.Scripts.Demo.Hooks.NotifyInterrupt
  end

  guardrails do
    input Moto.Scripts.Demo.Guardrails.BlockSecretPrompt
    output Moto.Scripts.Demo.Guardrails.BlockUnsafeReply
    tool Moto.Scripts.Demo.Guardrails.ApproveLargeMathTool
  end
end
