defmodule Jidoka.Examples.FeedbackSynthesizer.Demo do
  @moduledoc false

  alias Jidoka.Demo.{CLI, Debug, Inventory}
  alias Jidoka.Examples.FeedbackSynthesizer.Tools.{GroupThemes, LoadFeedback}

  @spec main([String.t()]) :: :ok
  def main(argv), do: CLI.run_command(argv, "feedback_synthesizer", fn -> :ok end, &run/2)

  @spec usage() :: :ok
  def usage, do: CLI.usage("feedback_synthesizer")

  defp run(options, log_level) do
    Inventory.print_compiled("Jidoka feedback synthesizer example", agent_module(), log_level,
      notice: "Canonical example: batch comments into themes, risks, and product actions.",
      try: [
        ~s(mix jidoka feedback_synthesizer --verify),
        ~s(mix jidoka feedback_synthesizer --dry-run --log-level trace),
        ~s(mix jidoka feedback_synthesizer -- "Synthesize feedback batch Q2-VOICE.")
      ]
    )

    CLI.print_log_status(log_level)

    cond do
      options.dry_run? -> IO.puts("Dry run: no agent started.")
      options.verify? -> verify!()
      true -> run_live(options.prompt, log_level)
    end
  end

  defp verify! do
    {:ok, batch} = LoadFeedback.run(%{batch_id: "Q2-VOICE"}, %{})
    {:ok, grouped} = GroupThemes.run(%{comments: batch.comments}, %{})

    parsed =
      finalize!(
        ~s({"themes":[{"name":"debuggability","count":2},{"name":"structured output operations","count":1},{"name":"examples","count":1}],) <>
          ~s("sentiment":"mixed","top_requests":["Export structured outputs","Improve failed tool debugging","Add approval and incident examples"],) <>
          ~s("risks":["Debugging gaps may slow production adoption."],) <>
          ~s("recommended_actions":["Prioritize trace UX","Ship more canonical examples"]})
      )

    unless length(grouped.themes) == 3 and length(parsed.top_requests) == 3 do
      raise Mix.Error, message: "feedback synthesizer verification failed"
    end

    IO.puts("Feedback synthesizer verification: ok")
    IO.inspect(batch, label: "batch")
    IO.inspect(grouped, label: "themes")
    IO.inspect(parsed, label: "structured_output")
    :ok
  end

  defp run_live(prompt, log_level) do
    CLI.ensure_api_key!()
    prompt = prompt || "Synthesize feedback batch Q2-VOICE."
    {:ok, pid} = agent_module().start_link(id: "feedback-synthesizer-live")
    Debug.maybe_enable_agent_debug(pid, log_level)

    try do
      result = agent_module().chat(pid, prompt, log_level: Debug.request_log_level(log_level))
      Debug.print_recent_events(pid, log_level)
      IO.inspect(result, label: "agent")
      :ok
    after
      Debug.safe_stop_agent(pid)
    end
  end

  defp finalize!(raw) do
    request_id = "feedback-synthesizer-#{System.unique_integer([:positive])}"

    agent =
      agent_module().runtime_module().new(id: "feedback-synthesizer-verify")
      |> Jido.AI.Request.start_request(request_id, "Synthesize feedback batch Q2-VOICE.")
      |> Jido.AI.Request.complete_request(request_id, raw)
      |> Jidoka.Output.finalize(request_id, agent_module().output())

    case Jido.AI.Request.get_result(agent, request_id) do
      {:ok, parsed} -> parsed
      other -> raise Mix.Error, message: "expected parsed feedback output, got: #{inspect(other)}"
    end
  end

  defp agent_module do
    Jidoka.Examples.FeedbackSynthesizer.Agents.FeedbackAgent
  end
end
