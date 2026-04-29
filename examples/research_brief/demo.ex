defmodule Jidoka.Examples.ResearchBrief.Demo do
  @moduledoc false

  alias Jidoka.Demo.{CLI, Debug, Inventory}
  alias Jidoka.Examples.ResearchBrief.Guardrails.RequireSources
  alias Jidoka.Examples.ResearchBrief.Tools.{LoadSources, RankSources}

  @spec main([String.t()]) :: :ok
  def main(argv), do: CLI.run_command(argv, "research_brief", fn -> :ok end, &run/2)

  @spec usage() :: :ok
  def usage, do: CLI.usage("research_brief")

  defp run(options, log_level) do
    Inventory.print_compiled("Jidoka research brief example", agent_module(), log_level,
      notice: "Canonical example: retrieve source snippets and produce a sourced brief.",
      try: [
        ~s(mix jidoka research_brief --verify),
        ~s(mix jidoka research_brief --dry-run --log-level trace),
        ~s(mix jidoka research_brief -- "Brief me on agent observability.")
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
    {:ok, loaded} = LoadSources.run(%{topic: "agent observability"}, %{})
    {:ok, ranked} = RankSources.run(%{sources: loaded.sources}, %{})

    parsed =
      finalize!(
        ~s({"brief":"Agent observability works best when traces, typed outputs, and approvals are visible together.",) <>
          ~s("key_points":["Timelines expose tool and model activity.","Structured outputs make automation safer.","Approvals protect risky side effects."],) <>
          ~s("sources":[{"id":"S1","rank":1},{"id":"S2","rank":2},{"id":"S3","rank":3}],) <>
          ~s("open_questions":["Which traces should be persisted first?"]})
      )

    :ok = RequireSources.call(output_guardrail_input(parsed))

    unless length(ranked.ranked_sources) == 3 and length(parsed.sources) == 3 do
      raise Mix.Error, message: "research brief verification failed"
    end

    IO.puts("Research brief verification: ok")
    IO.inspect(ranked, label: "ranked_sources")
    IO.inspect(parsed, label: "structured_output")
    :ok
  end

  defp run_live(prompt, log_level) do
    CLI.ensure_api_key!()
    prompt = prompt || "Brief me on agent observability."
    {:ok, pid} = agent_module().start_link(id: "research-brief-live")
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
    request_id = "research-brief-#{System.unique_integer([:positive])}"

    agent =
      agent_module().runtime_module().new(id: "research-brief-verify")
      |> Jido.AI.Request.start_request(request_id, "Brief me on agent observability.")
      |> Jido.AI.Request.complete_request(request_id, raw)
      |> Jidoka.Output.finalize(request_id, agent_module().output())

    case Jido.AI.Request.get_result(agent, request_id) do
      {:ok, parsed} -> parsed
      other -> raise Mix.Error, message: "expected parsed research output, got: #{inspect(other)}"
    end
  end

  defp output_guardrail_input(parsed) do
    %Jidoka.Guardrails.Output{
      agent: nil,
      server: self(),
      request_id: "research-brief-verify",
      message: "Brief me on agent observability.",
      context: %{},
      allowed_tools: nil,
      llm_opts: [],
      metadata: %{},
      request_opts: %{},
      outcome: {:ok, parsed}
    }
  end

  defp agent_module do
    Jidoka.Examples.ResearchBrief.Agents.ResearchAgent
  end
end
