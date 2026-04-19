for pattern <- ["tools/*.ex", "plugins/*.ex", "agents/*.ex"] do
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
    IO.puts("Running tool-call demo:")
    IO.puts("  #{prompt}")
    IO.puts("")
    one_shot(pid, prompt)
    IO.puts("")
  end

  defp one_shot(pid, prompt) do
    case ChatAgent.chat(pid, prompt) do
      {:ok, reply} ->
        IO.puts(reply)

      {:error, reason} ->
        IO.puts("error: #{inspect(reason)}")
        System.halt(1)
    end
  end

  defp interactive_loop(pid) do
    IO.puts("Enter a prompt. Type `exit` or press Ctrl-D to quit.")
    IO.puts("Try: Add 8 and 13.")
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
            case ChatAgent.chat(pid, prompt) do
              {:ok, reply} ->
                IO.puts("")
                IO.puts("claude> #{reply}")
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
end

Moto.Scripts.ChatAgentCLI.main(System.argv())
