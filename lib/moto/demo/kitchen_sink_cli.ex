defmodule Moto.Demo.KitchenSinkCLI do
  @moduledoc false

  alias Moto.Demo.{CLI, Debug, Inventory, Loader, Markdown}

  @spec main([String.t()]) :: :ok
  def main(argv) do
    Loader.load!(:kitchen_sink)

    case CLI.parse(argv) do
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
  def usage, do: CLI.usage("kitchen_sink")

  defp run(options, log_level) do
    print_header(log_level)
    CLI.print_log_status(log_level)

    CLI.with_started_agent(
      options,
      log_level,
      fn ->
        prepare_mcp_sandbox!()
        agent_module().start_link(id: "script-kitchen-sink-agent")
      end,
      &interactive_loop/2,
      &one_shot/3
    )
  end

  defp print_header(log_level) do
    Inventory.print_compiled("Moto kitchen sink demo", agent_module(), log_level,
      notice: "Showcase only: start with `mix moto chat` for the simple path.",
      try: [
        ~s(mix moto kitchen_sink -- "Add 17 and 25 with the tool."),
        ~s(mix moto kitchen_sink -- "Show what runtime context is visible."),
        ~s(mix moto kitchen_sink -- "Use the research_agent specialist to explain embeddings."),
        ~s(mix moto kitchen_sink -- "Use the editor_specialist to polish: Moto makes agents easier.")
      ]
    )
  end

  defp prepare_mcp_sandbox! do
    sandbox = Path.expand("../../../tmp/mcp-sandbox", __DIR__)
    File.mkdir_p!(sandbox)
    File.write!(Path.join(sandbox, "kitchen-sink.txt"), "hello from the Moto kitchen sink demo\n")
  end

  defp one_shot(pid, prompt, log_level) do
    case agent_module().chat(pid, prompt,
           context: %{notify_pid: self(), session: "kitchen-sink-cli"},
           log_level: Debug.request_log_level(log_level)
         ) do
      {:ok, reply} ->
        flush_interrupt_messages()
        print_last_subagent_calls(pid, log_level)
        Debug.print_recent_events(pid, log_level)
        Markdown.print_reply("agent", reply)

      {:interrupt, interrupt} ->
        flush_interrupt_messages()
        print_last_subagent_calls(pid, log_level)
        Debug.print_recent_events(pid, log_level)
        IO.puts("interrupt> #{interrupt.kind} - #{interrupt.message}")

      {:error, reason} ->
        flush_interrupt_messages()
        print_last_subagent_calls(pid, log_level)
        Debug.print_recent_events(pid, log_level)
        IO.puts("error> #{Moto.format_error(reason)}")
    end
  end

  defp interactive_loop(pid, log_level) do
    IO.puts("Type `exit` or press Ctrl-D to quit.")
    IO.puts("Try: Add 17 and 25 with the tool.")
    IO.puts("Try: Show what runtime context is visible.")
    IO.puts("Try: Use the research_agent specialist to explain embeddings.")
    IO.puts("Try: Use the editor_specialist to polish: Moto makes agents easier.")
    IO.puts("")
    loop(pid, log_level)
  end

  defp loop(pid, log_level) do
    case IO.gets("you> ") do
      :eof ->
        :ok

      {:error, _reason} ->
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

  defp flush_interrupt_messages do
    receive do
      {:kitchen_sink_interrupt, interrupt} ->
        tenant = get_in(interrupt.data, [:tenant])
        suffix = if tenant, do: " tenant=#{tenant}", else: ""
        IO.puts("hook> on_interrupt received #{interrupt.kind}#{suffix}: #{interrupt.message}")
        flush_interrupt_messages()
    after
      0 -> :ok
    end
  end

  defp print_last_subagent_calls(_pid, level) when level in [:debug, :trace], do: :ok

  defp print_last_subagent_calls(pid, :info) do
    case Moto.Subagent.latest_request_calls(pid) do
      [] ->
        :ok

      entries ->
        Enum.each(entries, fn entry ->
          IO.puts(
            "delegation> #{entry.name} mode=#{entry.mode} child=#{entry.child_id || "ephemeral"} status=#{subagent_status(entry)} duration_ms=#{entry[:duration_ms] || 0}"
          )
        end)
    end
  end

  defp subagent_status(%{outcome: :ok}), do: "ok"
  defp subagent_status(%{outcome: {:interrupt, _interrupt}}), do: "interrupt"
  defp subagent_status(%{outcome: {:error, reason}}), do: "error:#{Moto.format_error(reason)}"
  defp subagent_status(_entry), do: "unknown"

  defp agent_module do
    Module.concat([Moto, Examples, KitchenSink, Agents, KitchenSinkAgent])
  end
end
