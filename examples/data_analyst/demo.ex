defmodule Jidoka.Examples.DataAnalyst.Demo do
  @moduledoc false

  alias Jidoka.Demo.{CLI, Debug, Inventory}
  alias Jidoka.Examples.DataAnalyst.Tools.{ComparePeriods, QueryRevenue}

  @spec main([String.t()]) :: :ok
  def main(argv), do: CLI.run_command(argv, "data_analyst", fn -> :ok end, &run/2)

  @spec usage() :: :ok
  def usage, do: CLI.usage("data_analyst")

  defp run(options, log_level) do
    Inventory.print_compiled("Jidoka data analyst example", agent_module(), log_level,
      notice: "Canonical example: query fixture data, compare metrics, and explain the answer.",
      try: [
        ~s(mix jidoka data_analyst --verify),
        ~s(mix jidoka data_analyst --dry-run --log-level trace),
        ~s(mix jidoka data_analyst -- "How did core revenue change from February to March 2026?")
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
    {:ok, previous} = QueryRevenue.run(%{product: :core, period: "2026-02"}, %{})
    {:ok, current} = QueryRevenue.run(%{product: :core, period: "2026-03"}, %{})
    {:ok, comparison} = ComparePeriods.run(%{previous: previous.revenue, current: current.revenue}, %{})

    parsed =
      finalize!(
        ~s({"metric":"core revenue","value":151250.0,"comparison":"up 12.45% vs February 2026",) <>
          ~s("answer":"Core revenue increased to $151,250 in March 2026.",) <>
          ~s("caveats":["Fixture data only includes monthly revenue totals."]})
      )

    unless comparison.change_percent == 12.45 and parsed.value == current.revenue do
      raise Mix.Error, message: "data analyst verification failed"
    end

    IO.puts("Data analyst verification: ok")
    IO.inspect(previous, label: "previous")
    IO.inspect(current, label: "current")
    IO.inspect(comparison, label: "comparison")
    IO.inspect(parsed, label: "structured_output")
    :ok
  end

  defp run_live(prompt, log_level) do
    CLI.ensure_api_key!()
    prompt = prompt || "How did core revenue change from February to March 2026?"
    {:ok, pid} = agent_module().start_link(id: "data-analyst-live")
    Debug.maybe_enable_agent_debug(pid, log_level)

    try do
      result =
        agent_module().chat(pid, prompt,
          context: %{workspace: "demo-analytics", audience: "operator"},
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
    request_id = "data-analyst-#{System.unique_integer([:positive])}"

    agent =
      agent_module().runtime_module().new(id: "data-analyst-verify")
      |> Jido.AI.Request.start_request(request_id, "Compare core revenue.")
      |> Jido.AI.Request.complete_request(request_id, raw)
      |> Jidoka.Output.finalize(request_id, agent_module().output())

    case Jido.AI.Request.get_result(agent, request_id) do
      {:ok, parsed} -> parsed
      other -> raise Mix.Error, message: "expected parsed analyst output, got: #{inspect(other)}"
    end
  end

  defp agent_module do
    Jidoka.Examples.DataAnalyst.Agents.AnalystAgent
  end
end
