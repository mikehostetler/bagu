defmodule Jidoka.Examples.LeadQualification.Demo do
  @moduledoc false

  alias Jidoka.Demo.{CLI, Debug, Inventory}
  alias Jidoka.Examples.LeadQualification.Tools.{EnrichCompany, ScoreLead}

  @spec main([String.t()]) :: :ok
  def main(argv), do: CLI.run_command(argv, "lead_qualification", fn -> :ok end, &run/2)

  @spec usage() :: :ok
  def usage, do: CLI.usage("lead_qualification")

  defp run(options, log_level) do
    Inventory.print_compiled("Jidoka lead qualification example", agent_module(), log_level,
      notice: "Canonical example: enrich, score, and return CRM-ready typed output.",
      try: [
        ~s(mix jidoka lead_qualification --verify),
        ~s(mix jidoka lead_qualification --dry-run --log-level trace),
        ~s(mix jidoka lead_qualification -- "Qualify northwind.example.")
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
    {:ok, company} = EnrichCompany.run(%{domain: "northwind.example"}, %{})
    {:ok, score} = ScoreLead.run(Map.take(company, [:employees, :recent_signal]), %{})

    parsed =
      finalize!(
        ~s({"company":"Northwind Finance","segment":"enterprise","fit_score":95,) <>
          ~s("intent":"high","recommended_action":"solutions_engineer",) <>
          ~s("summary":"Enterprise finance lead with repeated pricing interest."})
      )

    unless score.fit_score == parsed.fit_score and score.recommended_action == parsed.recommended_action do
      raise Mix.Error, message: "lead qualification verification failed"
    end

    IO.puts("Lead qualification verification: ok")
    IO.inspect(company, label: "company")
    IO.inspect(score, label: "score")
    IO.inspect(parsed, label: "structured_output")
    :ok
  end

  defp run_live(prompt, log_level) do
    CLI.ensure_api_key!()
    prompt = prompt || "Qualify northwind.example."
    {:ok, pid} = agent_module().start_link(id: "lead-qualification-live")
    Debug.maybe_enable_agent_debug(pid, log_level)

    try do
      result =
        agent_module().chat(pid, prompt,
          context: %{territory: "na", source: "inbound"},
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
    request_id = "lead-qualification-#{System.unique_integer([:positive])}"

    agent =
      agent_module().runtime_module().new(id: "lead-qualification-verify")
      |> Jido.AI.Request.start_request(request_id, "Qualify northwind.example.")
      |> Jido.AI.Request.complete_request(request_id, raw)
      |> Jidoka.Output.finalize(request_id, agent_module().output())

    case Jido.AI.Request.get_result(agent, request_id) do
      {:ok, parsed} -> parsed
      other -> raise Mix.Error, message: "expected parsed lead output, got: #{inspect(other)}"
    end
  end

  defp agent_module do
    Jidoka.Examples.LeadQualification.Agents.LeadAgent
  end
end
