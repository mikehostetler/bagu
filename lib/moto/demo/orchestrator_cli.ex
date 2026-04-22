defmodule Moto.Demo.OrchestratorCLI do
  @moduledoc false

  alias Moto.Demo.{Debug, Inventory, Loader, Markdown}

  @switches [log_level: :string, dry_run: :boolean, help: :boolean]
  @aliases [l: :log_level]

  @spec main([String.t()]) :: :ok
  def main(argv) do
    Loader.load!(:orchestrator)

    case parse(argv) do
      {:ok, %{help?: true}} ->
        usage()

      {:ok, options} ->
        Debug.with_log_level(options.log_level, fn log_level ->
          run(options, log_level)
        end)

      {:error, message} ->
        raise Mix.Error, message: message
    end
  end

  @spec usage() :: :ok
  def usage do
    IO.puts("mix moto orchestrator [--log-level info|debug|trace] [--dry-run] [prompt]")
    :ok
  end

  defp parse(argv) do
    {opts, args, invalid} = OptionParser.parse(argv, strict: @switches, aliases: @aliases)

    cond do
      invalid != [] ->
        {:error,
         "invalid options: #{Enum.map_join(invalid, ", ", fn {key, _} -> "--#{key}" end)}"}

      opts[:help] ->
        {:ok, %{help?: true}}

      true ->
        with {:ok, log_level} <- Debug.parse_log_level(opts) do
          {:ok,
           %{
             help?: false,
             log_level: log_level,
             dry_run?: Keyword.get(opts, :dry_run, false),
             prompt: join_prompt(args)
           }}
        end
    end
  end

  defp run(options, log_level) do
    print_header(log_level)
    Debug.print_status(log_level)
    Debug.print_trace_status(log_level)

    if options.dry_run? do
      IO.puts("Dry run: no agent started.")
      :ok
    else
      ensure_api_key!()
      {:ok, pid} = agent_module().start_link(id: "script-orchestrator-agent")
      Debug.maybe_enable_agent_debug(pid, log_level)

      try do
        if options.prompt == nil do
          interactive_loop(pid, log_level)
        else
          one_shot(pid, options.prompt, log_level)
        end
      after
        Debug.safe_stop_agent(pid)
      end
    end
  end

  defp print_header(log_level) do
    Inventory.print_compiled("Moto orchestrator demo", agent_module(), log_level,
      try: [
        ~s(mix moto orchestrator -- "Use the research_agent specialist to explain vector databases."),
        ~s(mix moto orchestrator -- "Use the writer_specialist specialist to rewrite this copy: our setup is easier now.")
      ]
    )
  end

  defp ensure_api_key! do
    anthropic_api_key = Application.get_env(:req_llm, :anthropic_api_key)

    if is_nil(anthropic_api_key) or anthropic_api_key == "" do
      IO.puts("ANTHROPIC_API_KEY is not configured.")
      IO.puts("Add it to .env or export it in your shell.")
      System.halt(1)
    end
  end

  defp one_shot(pid, prompt, log_level) do
    case agent_module().chat(pid, prompt,
           context: %{session: "orchestrator-cli"},
           log_level: Debug.request_log_level(log_level)
         ) do
      {:ok, reply} ->
        print_last_subagent_calls(pid, log_level)
        Debug.print_recent_events(pid, log_level)
        Markdown.print_reply("agent", reply)

      {:interrupt, interrupt} ->
        print_last_subagent_calls(pid, log_level)
        Debug.print_recent_events(pid, log_level)
        IO.puts("interrupt> #{interrupt.kind} - #{interrupt.message}")

      {:error, reason} ->
        print_last_subagent_calls(pid, log_level)
        Debug.print_recent_events(pid, log_level)
        IO.puts("error> #{inspect(reason)}")
    end
  end

  defp interactive_loop(pid, log_level) do
    IO.puts("Type `exit` or press Ctrl-D to quit.")
    IO.puts("Try: Use the research_agent specialist to explain vector databases.")

    IO.puts(
      "Try: Use the writer_specialist specialist to rewrite this copy: our setup is easier now."
    )

    IO.puts("")
    loop(pid, log_level)
  end

  defp loop(pid, log_level) do
    case IO.gets("you> ") do
      nil ->
        :ok

      input ->
        prompt = String.trim(input)

        cond do
          prompt == "" ->
            loop(pid, log_level)

          prompt in ["exit", "quit"] ->
            :ok

          true ->
            one_shot(pid, prompt, log_level)
            IO.puts("")
            loop(pid, log_level)
        end
    end
  end

  defp print_last_subagent_calls(_pid, level) when level in [:debug, :trace], do: :ok

  defp print_last_subagent_calls(pid, :info) do
    case Moto.Subagent.latest_request_calls(pid) do
      [] ->
        IO.puts("delegation> none")

      entries ->
        Enum.each(entries, fn entry ->
          mode = entry.mode
          child_id = entry.child_id || "ephemeral"
          status = subagent_status(entry)
          duration = entry[:duration_ms] || 0
          result = entry[:result_preview]

          line =
            "delegation> #{entry.name} mode=#{mode} child=#{child_id} status=#{status} duration_ms=#{duration}"

          if is_binary(result) and result != "" do
            IO.puts(line <> " result=#{inspect(result)}")
          else
            IO.puts(line)
          end
        end)
    end
  end

  defp subagent_status(%{outcome: :ok}), do: "ok"
  defp subagent_status(%{outcome: {:interrupt, _interrupt}}), do: "interrupt"
  defp subagent_status(%{outcome: {:error, reason}}), do: "error:#{inspect(reason)}"
  defp subagent_status(entry), do: get_in(entry, [:child_result_meta, :status]) || "unknown"

  defp join_prompt([]), do: nil
  defp join_prompt(args), do: Enum.join(args, " ")

  defp agent_module do
    Module.concat([Moto, Examples, Orchestrator, Agents, ManagerAgent])
  end
end
