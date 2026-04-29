defmodule Jidoka.Examples.SupportTriage.Demo do
  @moduledoc false

  alias Jidoka.Demo.{CLI, Debug, Inventory}
  alias Jidoka.Examples.SupportTriage.Tools.{LoadTicket, RouteTicket}

  @spec main([String.t()]) :: :ok
  def main(argv), do: CLI.run_command(argv, "support_triage", fn -> :ok end, &run/2)

  @spec usage() :: :ok
  def usage, do: CLI.usage("support_triage")

  defp run(options, log_level) do
    Inventory.print_compiled("Jidoka support triage example", agent_module(), log_level,
      notice: "Canonical example: classify, route, and summarize an inbound support ticket.",
      try: [
        ~s(mix jidoka support_triage --verify),
        ~s(mix jidoka support_triage --dry-run --log-level trace),
        ~s(mix jidoka support_triage -- "Triage ticket TCK-1001.")
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
    {:ok, ticket} = LoadTicket.run(%{ticket_id: "TCK-1001"}, %{})
    {:ok, route} = RouteTicket.run(%{category: :billing, priority: :high}, %{})

    parsed =
      finalize!(
        ~s({"category":"billing","priority":"high","route":"billing_ops","needs_human":true,) <>
          ~s("summary":"Northwind Finance reports a duplicate invoice charge.",) <>
          ~s("next_action":"Send to billing operations for same-day invoice review."})
      )

    unless ticket.subject == "Duplicate invoice charge" and route.route == parsed.route and parsed.needs_human do
      raise Mix.Error, message: "support triage verification failed"
    end

    IO.puts("Support triage verification: ok")
    IO.inspect(ticket, label: "ticket")
    IO.inspect(route, label: "route")
    IO.inspect(parsed, label: "structured_output")
    :ok
  end

  defp run_live(prompt, log_level) do
    CLI.ensure_api_key!()
    prompt = prompt || "Triage ticket TCK-1001."
    {:ok, pid} = agent_module().start_link(id: "support-triage-live")
    Debug.maybe_enable_agent_debug(pid, log_level)

    try do
      result =
        agent_module().chat(pid, prompt, context: %{tenant: "demo"}, log_level: Debug.request_log_level(log_level))

      Debug.print_recent_events(pid, log_level)
      IO.inspect(result, label: "agent")
      :ok
    after
      Debug.safe_stop_agent(pid)
    end
  end

  defp finalize!(raw) do
    request_id = "support-triage-#{System.unique_integer([:positive])}"

    agent =
      agent_module().runtime_module().new(id: "support-triage-verify")
      |> Jido.AI.Request.start_request(request_id, "Triage ticket TCK-1001.")
      |> Jido.AI.Request.complete_request(request_id, raw)
      |> Jidoka.Output.finalize(request_id, agent_module().output())

    case Jido.AI.Request.get_result(agent, request_id) do
      {:ok, parsed} -> parsed
      other -> raise Mix.Error, message: "expected parsed support triage output, got: #{inspect(other)}"
    end
  end

  defp agent_module do
    Jidoka.Examples.SupportTriage.Agents.TriageAgent
  end
end
