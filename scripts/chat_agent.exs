for pattern <- ["tools/*.ex", "plugins/*.ex", "hooks/*.ex", "agents/*.ex"] do
  __DIR__
  |> Path.join("demo")
  |> Path.join(pattern)
  |> Path.wildcard()
  |> Enum.sort()
  |> Enum.each(&Code.require_file/1)
end

defmodule Moto.Scripts.ChatAgentCLI do
  alias Moto.Scripts.Demo.Agents.ChatAgent
  require Logger

  def main(argv) do
    argv = normalize_argv(argv)
    resolved_model = ChatAgent.model()
    anthropic_api_key = Application.get_env(:req_llm, :anthropic_api_key)
    demo_prompt =
      "Use the add_numbers tool to add 17 and 25. Do not do the math yourself. Reply with only the sum."

    Logger.configure(level: :error)

    IO.puts("Moto demo agent")
    IO.puts("Configured model: #{inspect(ChatAgent.configured_model())}")
    IO.puts("Resolved model: #{inspect(resolved_model)}")
    IO.puts("Plugins: #{Enum.join(ChatAgent.plugin_names(), ", ")}")
    IO.puts("Tools: #{Enum.join(ChatAgent.tool_names(), ", ")}")
    IO.puts("Before-turn hooks: #{Enum.map_join(ChatAgent.before_turn_hooks(), ", ", &inspect/1)}")
    IO.puts("After-turn hooks: #{Enum.map_join(ChatAgent.after_turn_hooks(), ", ", &inspect/1)}")
    IO.puts("Interrupt hooks: #{Enum.map_join(ChatAgent.interrupt_hooks(), ", ", &inspect/1)}")
    IO.puts("")

    if is_nil(anthropic_api_key) or anthropic_api_key == "" do
      IO.puts("ANTHROPIC_API_KEY is not configured.")
      IO.puts("Add it to .env or export it in your shell.")
      System.halt(1)
    end

    {:ok, pid} = ChatAgent.start_link(id: "script-chat-agent")

    try do
      case argv do
        [] ->
          run_demo(pid, demo_prompt)
          run_interrupt_demo(pid)
          interactive_loop(pid)

        _ -> one_shot(pid, Enum.join(argv, " "))
      end
    after
      :ok = Moto.stop_agent(pid)
    end
  end

  defp normalize_argv(["--" | rest]), do: rest
  defp normalize_argv(argv), do: argv

  defp run_demo(pid, prompt) do
    IO.puts("Running tool-call demo (before_turn + after_turn):")
    IO.puts("  #{prompt}")
    IO.puts("")
    one_shot(pid, prompt)
    IO.puts("")
  end

  defp run_interrupt_demo(pid) do
    prompt = "Refund order 123 for the customer."

    IO.puts("Running interrupt demo (after_turn + on_interrupt):")
    IO.puts("  #{prompt}")
    IO.puts("")
    one_shot(pid, prompt)
    IO.puts("")
  end

  defp one_shot(pid, prompt) do
    opts = [tool_context: %{notify_pid: self()}]

    case ChatAgent.chat(pid, prompt, opts) do
      {:ok, reply} ->
        flush_interrupt_messages()
        IO.puts(reply)

      {:interrupt, interrupt} ->
        flush_interrupt_messages()
        IO.puts("interrupt: #{interrupt.kind} - #{interrupt.message}")

      {:error, reason} ->
        IO.puts("error: #{inspect(reason)}")
        System.halt(1)
    end
  end

  defp interactive_loop(pid) do
    IO.puts("Enter a prompt. Type `exit` or press Ctrl-D to quit.")
    IO.puts("Try: Add 8 and 13.")
    IO.puts("Try: Refund order 123.")
    IO.puts("")
    loop(pid)
  end

  defp loop(pid) do
    case IO.gets("you> ") do
      nil ->
        :ok

      input ->
        prompt = String.trim(input)

        cond do
          prompt == "" ->
            loop(pid)

          prompt in ["exit", "quit"] ->
            :ok

          true ->
            case ChatAgent.chat(pid, prompt, tool_context: %{notify_pid: self()}) do
              {:ok, reply} ->
                flush_interrupt_messages()
                IO.puts("")
                IO.puts("claude> #{reply}")
                IO.puts("")
                loop(pid)

              {:interrupt, interrupt} ->
                flush_interrupt_messages()
                IO.puts("")
                IO.puts("interrupt> #{interrupt.kind} - #{interrupt.message}")
                IO.puts("")
                loop(pid)

              {:error, reason} ->
                IO.puts("")
                IO.puts("error> #{inspect(reason)}")
                IO.puts("")
                loop(pid)
            end
        end
    end
  end

  defp flush_interrupt_messages do
    receive do
      {:demo_interrupt, interrupt} ->
        IO.puts("hook> on_interrupt received #{interrupt.kind}: #{interrupt.message}")
        flush_interrupt_messages()
    after
      0 -> :ok
    end
  end
end

Moto.Scripts.ChatAgentCLI.main(System.argv())
