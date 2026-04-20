defmodule Moto.Demo.Loader do
  @moduledoc false

  @chat_files [
    "demo/tools/add_numbers.ex",
    "demo/plugins/math_plugin.ex",
    "demo/hooks/reply_with_final_answer.ex",
    "demo/hooks/tag_after_turn.ex",
    "demo/hooks/require_approval_for_refunds.ex",
    "demo/hooks/notify_interrupt.ex",
    "demo/guardrails/block_secret_prompt.ex",
    "demo/guardrails/block_unsafe_reply.ex",
    "demo/guardrails/approve_large_math_tool.ex",
    "demo/agents/chat_agent.ex"
  ]

  @orchestrator_files [
    "orchestrator_demo/subagents/imported_writer_specialist.ex",
    "orchestrator_demo/agents/research_agent.ex",
    "orchestrator_demo/agents/manager_agent.ex"
  ]

  @spec load!(:chat | :orchestrator) :: :ok
  def load!(:chat) do
    require_demo_files(@chat_files)
  end

  def load!(:orchestrator) do
    require_demo_files(@orchestrator_files)
  end

  defp require_demo_files(paths) do
    script_root = Path.expand("../../../scripts", __DIR__)

    paths
    |> Enum.map(&Path.join(script_root, &1))
    |> Enum.each(&Code.require_file/1)

    :ok
  end
end
