defmodule Jidoka.Examples.PrReviewer.Demo do
  @moduledoc false

  alias Jidoka.Demo.{CLI, Debug, Inventory}
  alias Jidoka.Examples.PrReviewer.Guardrails.BlockStyleOnlyReview
  alias Jidoka.Examples.PrReviewer.Tools.{DetectReviewFindings, LoadDiff}

  @spec main([String.t()]) :: :ok
  def main(argv), do: CLI.run_command(argv, "pr_reviewer", fn -> :ok end, &run/2)

  @spec usage() :: :ok
  def usage, do: CLI.usage("pr_reviewer")

  defp run(options, log_level) do
    Inventory.print_compiled("Jidoka PR reviewer example", agent_module(), log_level,
      notice: "Canonical example: review a fixture diff and return severity-ranked findings.",
      try: [
        ~s(mix jidoka pr_reviewer --verify),
        ~s(mix jidoka pr_reviewer --dry-run --log-level trace),
        ~s(mix jidoka pr_reviewer -- "Review PR-17.")
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
    {:ok, diff} = LoadDiff.run(%{pr_id: "PR-17"}, %{})
    {:ok, detected} = DetectReviewFindings.run(%{diff: diff.diff}, %{})

    parsed =
      finalize!(
        ~s({"summary":"One high-priority refund approval issue was found.",) <>
          ~s("findings":[{"priority":"P1","file":"lib/refunds.ex","line":2,"title":"Refund execution bypasses approval","body":"Payment.refund is called without an approval check."}],) <>
          ~s("test_gaps":["Add a test that unapproved refunds are rejected."],) <>
          ~s("recommended_next_steps":["Require approval before calling Payment.refund."]})
      )

    :ok = BlockStyleOnlyReview.call(output_guardrail_input(parsed))

    unless length(detected.findings) == 1 and length(parsed.findings) == 1 do
      raise Mix.Error, message: "PR reviewer verification failed"
    end

    IO.puts("PR reviewer verification: ok")
    IO.inspect(detected, label: "detected")
    IO.inspect(parsed, label: "structured_output")
    :ok
  end

  defp run_live(prompt, log_level) do
    CLI.ensure_api_key!()
    prompt = prompt || "Review PR-17."
    {:ok, pid} = agent_module().start_link(id: "pr-reviewer-live")
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
    request_id = "pr-reviewer-#{System.unique_integer([:positive])}"

    agent =
      agent_module().runtime_module().new(id: "pr-reviewer-verify")
      |> Jido.AI.Request.start_request(request_id, "Review PR-17.")
      |> Jido.AI.Request.complete_request(request_id, raw)
      |> Jidoka.Output.finalize(request_id, agent_module().output())

    case Jido.AI.Request.get_result(agent, request_id) do
      {:ok, parsed} -> parsed
      other -> raise Mix.Error, message: "expected parsed review output, got: #{inspect(other)}"
    end
  end

  defp output_guardrail_input(parsed) do
    %Jidoka.Guardrails.Output{
      agent: nil,
      server: self(),
      request_id: "pr-reviewer-verify",
      message: "Review PR-17.",
      context: %{},
      allowed_tools: nil,
      llm_opts: [],
      metadata: %{},
      request_opts: %{},
      outcome: {:ok, parsed}
    }
  end

  defp agent_module do
    Jidoka.Examples.PrReviewer.Agents.ReviewerAgent
  end
end
