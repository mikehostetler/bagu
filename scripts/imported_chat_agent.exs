for pattern <- ["tools/*.ex", "plugins/*.ex", "hooks/*.ex", "agents/*.ex"] do
  __DIR__
  |> Path.join("demo")
  |> Path.join(pattern)
  |> Path.wildcard()
  |> Enum.sort()
  |> Enum.each(&Code.require_file/1)
end

defmodule Moto.Scripts.ImportedChatAgentCLI do
  alias Moto.DynamicAgent
  alias Moto.Scripts.Demo.Tools.AddNumbers
  alias Moto.Scripts.Demo.Hooks.ReplyWithFinalAnswer
  require Logger

  def main(argv) do
    argv = normalize_argv(argv)
    anthropic_api_key = Application.get_env(:req_llm, :anthropic_api_key)
    spec_path = sample_spec_path()
    available_tools = [AddNumbers]
    available_hooks = [ReplyWithFinalAnswer]
    {:ok, tool_registry} = Moto.Tool.normalize_available_tools(available_tools)
    {:ok, hook_registry} = Moto.Hook.normalize_available_hooks(available_hooks)

    demo_prompt =
      "Use the add_numbers tool to add 17 and 25. Do not do the math yourself. Reply with only the sum."

    Logger.configure(level: :error)

    IO.puts("Moto imported-agent demo")
    IO.puts("Spec file: #{spec_path}")
    IO.puts("Available tools: #{Enum.join(Map.keys(tool_registry), ", ")}")
    IO.puts("Available hooks: #{Enum.join(Map.keys(hook_registry), ", ")}")
    IO.puts("")

    if is_nil(anthropic_api_key) or anthropic_api_key == "" do
      IO.puts("ANTHROPIC_API_KEY is not configured.")
      IO.puts("Add it to .env or export it in your shell.")
      System.halt(1)
    end

    agent =
      Moto.import_agent_file!(spec_path,
        available_tools: available_tools,
        available_hooks: available_hooks
      )
    print_agent_details(agent)

    {:ok, pid} = Moto.start_agent(agent, id: "imported-script-chat-agent")

    try do
      case argv do
        [] ->
          run_demo(pid, demo_prompt)
          interactive_loop(pid)

        _ ->
          one_shot(pid, Enum.join(argv, " "))
      end
    after
      :ok = Moto.stop_agent(pid)
    end
  end

  defp sample_spec_path do
    :moto
    |> :code.priv_dir()
    |> to_string()
    |> Path.join("moto/sample_math_agent.json")
  end

  defp print_agent_details(%DynamicAgent{spec: spec, tool_modules: tool_modules, hook_modules: hook_modules}) do
    IO.puts("Imported agent: #{spec.name}")
    IO.puts("Configured model: #{inspect(spec.model)}")
    IO.puts("Resolved model: #{inspect(Moto.model(spec.model))}")
    IO.puts("Default context: #{inspect(spec.context)}")
    IO.puts("Imported tools: #{Enum.join(spec.tools, ", ")}")
    IO.puts("Imported hooks: #{format_imported_hooks(spec.hooks)}")
    IO.puts("Tool modules: #{Enum.map_join(tool_modules, ", ", &inspect/1)}")
    IO.puts("Hook modules: #{format_hook_modules(hook_modules)}")
    IO.puts("")
  end

  defp format_imported_hooks(hooks) do
    hooks
    |> Enum.filter(fn {_stage, names} -> names != [] end)
    |> Enum.map_join(", ", fn {stage, names} -> "#{stage}=#{Enum.join(names, "|")}" end)
    |> case do
      "" -> "(none)"
      value -> value
    end
  end

  defp format_hook_modules(hooks) do
    hooks
    |> Enum.filter(fn {_stage, modules} -> modules != [] end)
    |> Enum.map_join(", ", fn {stage, modules} ->
      "#{stage}=#{Enum.map_join(modules, "|", &inspect/1)}"
    end)
    |> case do
      "" -> "(none)"
      value -> value
    end
  end

  defp normalize_argv(["--" | rest]), do: rest
  defp normalize_argv(argv), do: argv

  defp run_demo(pid, prompt) do
    IO.puts("Running imported-agent tool-call demo:")
    IO.puts("  #{prompt}")
    IO.puts("")
    one_shot(pid, prompt)
    IO.puts("")
  end

  defp one_shot(pid, prompt) do
    case Moto.chat(pid, prompt, context: %{"session" => "imported-cli"}) do
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
            case Moto.chat(pid, prompt, context: %{"session" => "imported-interactive"}) do
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

Moto.Scripts.ImportedChatAgentCLI.main(System.argv())
