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

  plugins do
    plugin Moto.Scripts.Demo.Plugins.MathPlugin
  end

  hooks do
    before_turn Moto.Scripts.Demo.Hooks.ReplyWithFinalAnswer
    after_turn Moto.Scripts.Demo.Hooks.TagAfterTurn
    after_turn Moto.Scripts.Demo.Hooks.RequireApprovalForRefunds
    on_interrupt Moto.Scripts.Demo.Hooks.NotifyInterrupt
  end
end
