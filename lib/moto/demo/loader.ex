defmodule Moto.Demo.Loader do
  @moduledoc false

  @chat_files [
    "chat/tools/add_numbers.ex",
    "chat/plugins/math_plugin.ex",
    "chat/hooks/reply_with_final_answer.ex",
    "chat/hooks/tag_after_turn.ex",
    "chat/hooks/require_approval_for_refunds.ex",
    "chat/hooks/notify_interrupt.ex",
    "chat/guardrails/block_secret_prompt.ex",
    "chat/guardrails/block_unsafe_reply.ex",
    "chat/guardrails/approve_large_math_tool.ex",
    "chat/agents/chat_agent.ex"
  ]

  @orchestrator_files [
    "orchestrator/subagents/imported_writer_specialist.ex",
    "orchestrator/agents/research_agent.ex",
    "orchestrator/agents/manager_agent.ex"
  ]

  @kitchen_sink_files [
    "kitchen_sink/prompts/dynamic_prompt.ex",
    "kitchen_sink/tools/add_numbers.ex",
    "kitchen_sink/tools/show_context.ex",
    "kitchen_sink/plugins/showcase_plugin.ex",
    "kitchen_sink/hooks/shape_turn.ex",
    "kitchen_sink/hooks/tag_reply.ex",
    "kitchen_sink/hooks/notify_interrupt.ex",
    "kitchen_sink/guardrails/block_classified_prompt.ex",
    "kitchen_sink/guardrails/block_unsafe_reply.ex",
    "kitchen_sink/guardrails/approve_large_math_tool.ex",
    "kitchen_sink/agents/research_agent.ex",
    "kitchen_sink/subagents/imported_editor_specialist.ex",
    "kitchen_sink/agents/kitchen_sink_agent.ex"
  ]

  @workflow_files [
    "workflow/tools/add_amount.ex",
    "workflow/tools/double_value.ex",
    "workflow/workflows/math_pipeline.ex"
  ]

  @spec load!(:chat | :orchestrator | :kitchen_sink | :workflow) :: :ok
  def load!(:chat) do
    require_demo_files(@chat_files)
  end

  def load!(:orchestrator) do
    require_demo_files(@orchestrator_files)
  end

  def load!(:kitchen_sink) do
    require_demo_files(@kitchen_sink_files)
  end

  def load!(:workflow) do
    require_demo_files(@workflow_files)
  end

  defp require_demo_files(paths) do
    example_root = Path.expand("../../../examples", __DIR__)

    paths
    |> Enum.map(&Path.join(example_root, &1))
    |> Enum.each(&Code.require_file/1)

    :ok
  end
end
