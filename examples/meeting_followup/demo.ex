defmodule Jidoka.Examples.MeetingFollowup.Demo do
  @moduledoc false

  alias Jidoka.Demo.{CLI, Debug, Inventory}
  alias Jidoka.Examples.MeetingFollowup.Tools.{ExtractActionItems, LoadMeetingNotes}

  @spec main([String.t()]) :: :ok
  def main(argv), do: CLI.run_command(argv, "meeting_followup", fn -> :ok end, &run/2)

  @spec usage() :: :ok
  def usage, do: CLI.usage("meeting_followup")

  defp run(options, log_level) do
    Inventory.print_compiled("Jidoka meeting follow-up example", agent_module(), log_level,
      notice: "Canonical example: turn meeting notes into decisions, tasks, risks, and follow-up copy.",
      try: [
        ~s(mix jidoka meeting_followup --verify),
        ~s(mix jidoka meeting_followup --dry-run --log-level trace),
        ~s(mix jidoka meeting_followup -- "Create follow-up for meeting CS-42.")
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
    {:ok, meeting} = LoadMeetingNotes.run(%{meeting_id: "CS-42"}, %{})
    {:ok, extracted} = ExtractActionItems.run(%{notes: meeting.notes}, %{})

    parsed =
      finalize!(
        ~s({"summary":"Northwind is ready for a May 6 pilot if SSO docs and sandbox access land this week.",) <>
          ~s("decisions":["Launch the pilot on May 6."],) <>
          ~s("action_items":[{"owner":"Maya","task":"Send sandbox invite","due":"Friday"},{"owner":"Luis","task":"Send SSO documentation","due":"Friday"}],) <>
          ~s("risks":["Billing export remains blocked."],) <>
          ~s("follow_up_email":"Thanks for the productive check-in. We will prepare the sandbox invite and SSO docs by Friday, then target the May 6 pilot."})
      )

    :ok =
      Jidoka.Examples.MeetingFollowup.Guardrails.BlockUnsupportedCommitments.call(output_guardrail_input(parsed))

    unless extracted.count == 2 and length(parsed.action_items) == 2 do
      raise Mix.Error, message: "meeting follow-up verification failed"
    end

    IO.puts("Meeting follow-up verification: ok")
    IO.inspect(meeting, label: "meeting")
    IO.inspect(extracted, label: "extracted")
    IO.inspect(parsed, label: "structured_output")
    :ok
  end

  defp run_live(prompt, log_level) do
    CLI.ensure_api_key!()
    prompt = prompt || "Create follow-up for meeting CS-42."
    {:ok, pid} = agent_module().start_link(id: "meeting-followup-live")
    Debug.maybe_enable_agent_debug(pid, log_level)

    try do
      result =
        agent_module().chat(pid, prompt,
          context: %{workspace: "customer-success"},
          log_level: Debug.request_log_level(log_level)
        )

      Debug.print_recent_events(pid, log_level)
      IO.inspect(result, label: "agent")
      :ok
    after
      Debug.safe_stop_agent(pid)
    end
  end

  defp finalize!(raw) do
    request_id = "meeting-followup-#{System.unique_integer([:positive])}"

    agent =
      agent_module().runtime_module().new(id: "meeting-followup-verify")
      |> Jido.AI.Request.start_request(request_id, "Create follow-up for meeting CS-42.")
      |> Jido.AI.Request.complete_request(request_id, raw)
      |> Jidoka.Output.finalize(request_id, agent_module().output())

    case Jido.AI.Request.get_result(agent, request_id) do
      {:ok, parsed} -> parsed
      other -> raise Mix.Error, message: "expected parsed meeting output, got: #{inspect(other)}"
    end
  end

  defp output_guardrail_input(parsed) do
    %Jidoka.Guardrails.Output{
      agent: nil,
      server: self(),
      request_id: "meeting-followup-verify",
      message: "Create follow-up for meeting CS-42.",
      context: %{},
      allowed_tools: nil,
      llm_opts: [],
      metadata: %{},
      request_opts: %{},
      outcome: {:ok, parsed}
    }
  end

  defp agent_module do
    Jidoka.Examples.MeetingFollowup.Agents.FollowUpAgent
  end
end
