demo_root = Path.join(__DIR__, "orchestrator_demo")

[
  "subagents/imported_writer_specialist.ex",
  "agents/research_agent.ex",
  "agents/manager_agent.ex"
]
|> Enum.map(&Path.join(demo_root, &1))
|> Enum.each(&Code.require_file/1)

defmodule Moto.Scripts.OrchestratorAgentCLI do
  alias Moto.Scripts.OrchestratorDemo.Agents.ManagerAgent
  require Logger

  def main(argv) do
    argv = normalize_argv(argv)
    anthropic_api_key = Application.get_env(:req_llm, :anthropic_api_key)

    Logger.configure(level: :error)

    IO.puts("Moto orchestrator demo")
    IO.puts("Configured model: #{inspect(ManagerAgent.configured_model())}")
    IO.puts("Resolved model: #{inspect(ManagerAgent.model())}")
    IO.puts("Default context: #{inspect(ManagerAgent.context())}")
    IO.puts("Subagents: #{Enum.join(ManagerAgent.subagent_names(), ", ")}")
    IO.puts("Tools: #{Enum.join(ManagerAgent.tool_names(), ", ")}")
    IO.puts("")

    if is_nil(anthropic_api_key) or anthropic_api_key == "" do
      IO.puts("ANTHROPIC_API_KEY is not configured.")
      IO.puts("Add it to .env or export it in your shell.")
      System.halt(1)
    end

    {:ok, pid} = ManagerAgent.start_link(id: "script-orchestrator-agent")

    try do
      case argv do
        [] ->
          run_demo(
            pid,
            "Use the research_agent specialist to give three concise reasons why hexagonal architecture is useful. Reply with only the specialist result."
          )

          run_demo(
            pid,
            "Use the writer_specialist specialist to rewrite this line for a product launch: 'our sync is faster now'. Reply with only the rewritten copy."
          )

          interactive_loop(pid)

        _ ->
          one_shot(pid, Enum.join(argv, " "))
      end
    after
      :ok = Moto.stop_agent(pid)
    end
  end

  defp normalize_argv(["--" | rest]), do: rest
  defp normalize_argv(argv), do: argv

  defp run_demo(pid, prompt) do
    IO.puts("Running orchestration demo:")
    IO.puts("  #{prompt}")
    IO.puts("")
    one_shot(pid, prompt)
    IO.puts("")
  end

  defp one_shot(pid, prompt) do
    case ManagerAgent.chat(pid, prompt, context: %{session: "orchestrator-cli"}) do
      {:ok, reply} ->
        IO.puts(reply)
        print_last_subagent_calls(pid)

      {:interrupt, interrupt} ->
        IO.puts("interrupt: #{interrupt.kind} - #{interrupt.message}")
        print_last_subagent_calls(pid)

      {:error, reason} ->
        IO.puts("error: #{inspect(reason)}")
        print_last_subagent_calls(pid)
    end
  end

  defp interactive_loop(pid) do
    IO.puts("Enter a prompt. Type `exit` or press Ctrl-D to quit.")
    IO.puts("Try: Use the research_agent specialist to explain vector databases.")
    IO.puts("Try: Use the writer_specialist specialist to rewrite this copy: our setup is easier now.")
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
            one_shot(pid, prompt)
            IO.puts("")
            loop(pid)
        end
    end
  end

  defp print_last_subagent_calls(pid) do
    case Jido.AgentServer.state(pid) do
      {:ok, %{agent: agent}} ->
        request_id = agent.state.last_request_id

        calls =
          get_in(agent.state, [:requests, request_id, :meta, :moto_subagents, :calls]) || []

        case calls do
          [] ->
            IO.puts("subagents> none")

          entries ->
            Enum.each(entries, fn entry ->
              mode = entry.mode
              child_id = entry.child_id || "ephemeral"
              IO.puts("subagents> #{entry.name} mode=#{mode} child=#{child_id}")
            end)
        end

      _ ->
        IO.puts("subagents> unavailable")
    end
  end
end

Moto.Scripts.OrchestratorAgentCLI.main(System.argv())
