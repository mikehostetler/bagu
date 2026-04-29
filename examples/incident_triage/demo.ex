defmodule Jidoka.Examples.IncidentTriage.Demo do
  @moduledoc false

  alias Jidoka.Demo.{CLI, Debug, Inventory}
  alias Jidoka.Examples.IncidentTriage.Workflows.InvestigateIncident

  @spec main([String.t()]) :: :ok
  def main(argv), do: CLI.run_command(argv, "incident_triage", fn -> :ok end, &run/2)

  @spec usage() :: :ok
  def usage, do: CLI.usage("incident_triage")

  defp run(options, log_level) do
    Inventory.print_compiled("Jidoka incident triage example", agent_module(), log_level,
      notice: "Canonical example: expose an ordered workflow as an agent tool.",
      try: [
        ~s(mix jidoka incident_triage --verify),
        ~s(mix jidoka incident_triage --dry-run --log-level trace),
        ~s(mix jidoka incident_triage -- "Investigate alert ALERT-9.")
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
    {:ok, workflow_output} = InvestigateIncident.run(%{alert_id: "ALERT-9"})

    parsed =
      finalize!(
        ~s({"severity":"sev2","affected_service":"checkout-api",) <>
          ~s("likely_causes":["Recent deploy checkout-api@2026.04.29.2","payment adapter timeout spike"],) <>
          ~s("recommended_actions":["Page checkout owner","Inspect payment adapter timeout logs","Prepare rollback"],) <>
          ~s("escalate":true})
      )

    unless workflow_output.affected_service == parsed.affected_service and parsed.escalate do
      raise Mix.Error, message: "incident triage verification failed"
    end

    IO.puts("Incident triage verification: ok")
    IO.puts("Workflow steps: classify -> snapshot")
    IO.inspect(workflow_output, label: "workflow_output")
    IO.inspect(parsed, label: "structured_output")
    :ok
  end

  defp run_live(prompt, log_level) do
    CLI.ensure_api_key!()
    prompt = prompt || "Investigate alert ALERT-9."
    {:ok, pid} = agent_module().start_link(id: "incident-triage-live")
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
    request_id = "incident-triage-#{System.unique_integer([:positive])}"

    agent =
      agent_module().runtime_module().new(id: "incident-triage-verify")
      |> Jido.AI.Request.start_request(request_id, "Investigate alert ALERT-9.")
      |> Jido.AI.Request.complete_request(request_id, raw)
      |> Jidoka.Output.finalize(request_id, agent_module().output())

    case Jido.AI.Request.get_result(agent, request_id) do
      {:ok, parsed} -> parsed
      other -> raise Mix.Error, message: "expected parsed incident output, got: #{inspect(other)}"
    end
  end

  defp agent_module do
    Jidoka.Examples.IncidentTriage.Agents.IncidentAgent
  end
end
