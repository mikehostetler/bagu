defmodule Moto.Demo.ChatCLI do
  @moduledoc false

  alias Moto.Demo.{CLI, Debug, Inventory, Loader, Markdown}

  @spec main([String.t()]) :: :ok
  def main(argv) do
    Loader.load!(:chat)

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
  def usage, do: CLI.usage("chat")

  defp run(options, log_level) do
    print_header(log_level)
    CLI.print_log_status(log_level)

    CLI.with_started_agent(
      options,
      log_level,
      fn -> agent_module().start_link(id: "script-chat-agent") end,
      &interactive_loop/2,
      &one_shot/3
    )
  end

  defp print_header(log_level) do
    Inventory.print_compiled("Moto chat demo", agent_module(), log_level,
      try: [
        ~s(mix moto chat -- "Add 8 and 13."),
        ~s(mix moto chat -- "Remember that my favorite color is blue.")
      ]
    )
  end

  defp one_shot(pid, prompt, log_level) do
    one_shot(pid, prompt, log_level, session: "cli")
  end

  defp one_shot(pid, prompt, log_level, opts) when is_list(opts) do
    chat_agent = agent_module()
    session = Keyword.get(opts, :session, "cli")

    chat_opts = [
      context: %{notify_pid: self(), session: session},
      log_level: Debug.request_log_level(log_level)
    ]

    case chat_agent.chat(pid, prompt, chat_opts) do
      {:ok, reply} ->
        flush_interrupt_messages()
        Debug.print_recent_events(pid, log_level)
        Markdown.print_reply("agent", reply)

      {:interrupt, interrupt} ->
        flush_interrupt_messages()
        Debug.print_recent_events(pid, log_level)
        IO.puts("interrupt> #{interrupt.kind} - #{interrupt.message}")

      {:error, reason} ->
        flush_interrupt_messages()
        Debug.print_recent_events(pid, log_level)
        IO.puts("error> #{inspect(reason)}")
    end
  end

  defp interactive_loop(pid, log_level) do
    IO.puts("Type `exit` or press Ctrl-D to quit.")
    IO.puts("Try: Add 8 and 13.")
    IO.puts("Try: Remember that my favorite color is blue.")
    IO.puts("")
    loop(pid, log_level)
  end

  defp loop(pid, log_level) do
    chat_agent = agent_module()

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
            case chat_agent.chat(pid, prompt,
                   context: %{notify_pid: self(), session: "interactive"},
                   log_level: Debug.request_log_level(log_level)
                 ) do
              {:ok, reply} ->
                flush_interrupt_messages()
                IO.puts("")
                Debug.print_recent_events(pid, log_level)
                Markdown.print_reply("agent", reply)
                IO.puts("")
                loop(pid, log_level)

              {:interrupt, interrupt} ->
                flush_interrupt_messages()
                IO.puts("")
                IO.puts("interrupt> #{interrupt.kind} - #{interrupt.message}")
                Debug.print_recent_events(pid, log_level)
                IO.puts("")
                loop(pid, log_level)

              {:error, reason} ->
                flush_interrupt_messages()
                IO.puts("")
                IO.puts("error> #{inspect(reason)}")
                Debug.print_recent_events(pid, log_level)
                IO.puts("")
                loop(pid, log_level)
            end
        end
    end
  end

  defp flush_interrupt_messages do
    receive do
      {:demo_interrupt, interrupt} ->
        tenant = get_in(interrupt.data, [:tenant])
        tenant_suffix = if tenant, do: " tenant=#{tenant}", else: ""

        IO.puts(
          "hook> on_interrupt received #{interrupt.kind}#{tenant_suffix}: #{interrupt.message}"
        )

        flush_interrupt_messages()
    after
      0 -> :ok
    end
  end

  defp agent_module do
    Module.concat([Moto, Examples, Chat, Agents, ChatAgent])
  end
end
