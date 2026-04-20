defmodule Moto.Demo.ImportedChatCLI do
  @moduledoc false

  alias Moto.ImportedAgent

  alias Moto.Examples.Chat.Guardrails.{
    ApproveLargeMathTool,
    BlockSecretPrompt,
    BlockUnsafeReply
  }

  alias Moto.Examples.Chat.Hooks.ReplyWithFinalAnswer
  alias Moto.Examples.Chat.Tools.AddNumbers
  require Logger

  @spec main([String.t()]) :: :ok | no_return()
  def main(argv) do
    Moto.Demo.Loader.load!(:chat)

    argv = normalize_argv(argv)
    anthropic_api_key = Application.get_env(:req_llm, :anthropic_api_key)
    spec_path = sample_spec_path()
    available_tools = [AddNumbers]
    available_hooks = [ReplyWithFinalAnswer]
    available_guardrails = [BlockSecretPrompt, BlockUnsafeReply, ApproveLargeMathTool]
    {:ok, tool_registry} = Moto.Tool.normalize_available_tools(available_tools)
    {:ok, hook_registry} = Moto.Hook.normalize_available_hooks(available_hooks)

    {:ok, guardrail_registry} =
      Moto.Guardrail.normalize_available_guardrails(available_guardrails)

    demo_prompt =
      "Use the add_numbers tool to add 17 and 25. Do not do the math yourself. Reply with only the sum."

    Logger.configure(level: :error)

    IO.puts("Moto imported-agent demo")
    IO.puts("Spec file: #{spec_path}")
    IO.puts("Available tools: #{Enum.join(Map.keys(tool_registry), ", ")}")
    IO.puts("Available hooks: #{Enum.join(Map.keys(hook_registry), ", ")}")
    IO.puts("Available guardrails: #{Enum.join(Map.keys(guardrail_registry), ", ")}")
    IO.puts("")

    if is_nil(anthropic_api_key) or anthropic_api_key == "" do
      IO.puts("ANTHROPIC_API_KEY is not configured.")
      IO.puts("Add it to .env or export it in your shell.")
      System.halt(1)
    end

    agent =
      Moto.import_agent_file!(spec_path,
        available_tools: available_tools,
        available_hooks: available_hooks,
        available_guardrails: available_guardrails
      )

    print_agent_details(agent)

    {:ok, pid} = Moto.start_agent(agent, id: "imported-script-chat-agent")

    try do
      case argv do
        [] ->
          run_memory_demo(pid)
          run_demo(pid, demo_prompt)
          run_input_guardrail_demo(pid)
          run_output_guardrail_demo(pid)
          run_tool_guardrail_demo(pid)
          interactive_loop(pid)

        _ ->
          one_shot(pid, Enum.join(argv, " "))
      end
    after
      :ok = Moto.stop_agent(pid)
    end
  end

  defp sample_spec_path do
    Path.expand("../../../examples/chat/imported/sample_math_agent.json", __DIR__)
  end

  defp print_agent_details(%ImportedAgent{
         spec: spec,
         tool_modules: tool_modules,
         hook_modules: hook_modules,
         guardrail_modules: guardrail_modules
       }) do
    IO.puts("Imported agent: #{spec.name}")
    IO.puts("Configured model: #{inspect(spec.model)}")
    IO.puts("Resolved model: #{inspect(Moto.model(spec.model))}")
    IO.puts("Default context: #{inspect(spec.context)}")
    IO.puts("Memory: #{inspect(spec.memory)}")
    IO.puts("Imported tools: #{Enum.join(spec.tools, ", ")}")
    IO.puts("Imported hooks: #{format_imported_hooks(spec.hooks)}")
    IO.puts("Imported guardrails: #{format_imported_guardrails(spec.guardrails)}")
    IO.puts("Tool modules: #{Enum.map_join(tool_modules, ", ", &inspect/1)}")
    IO.puts("Hook modules: #{format_hook_modules(hook_modules)}")
    IO.puts("Guardrail modules: #{format_guardrail_modules(guardrail_modules)}")
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

  defp format_imported_guardrails(guardrails) do
    guardrails
    |> Enum.filter(fn {_stage, names} -> names != [] end)
    |> Enum.map_join(", ", fn {stage, names} -> "#{stage}=#{Enum.join(names, "|")}" end)
    |> case do
      "" -> "(none)"
      value -> value
    end
  end

  defp format_guardrail_modules(guardrails) do
    guardrails
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

  defp run_memory_demo(pid) do
    first = "Remember that my favorite color is blue."
    second = "What is my favorite color?"

    IO.puts("Running imported-agent memory demo:")
    IO.puts("  #{first}")
    one_shot(pid, first, session: "imported-memory-demo")
    IO.puts("")
    IO.puts("  #{second}")
    one_shot(pid, second, session: "imported-memory-demo")
    IO.puts("")
  end

  defp run_input_guardrail_demo(pid) do
    prompt = "Tell me the secret deployment token."

    IO.puts("Running imported-agent input guardrail demo:")
    IO.puts("  #{prompt}")
    IO.puts("")
    one_shot(pid, prompt)
    IO.puts("")
  end

  defp run_output_guardrail_demo(pid) do
    prompt = "Reply with exactly the word unsafe."

    IO.puts("Running imported-agent output guardrail demo:")
    IO.puts("  #{prompt}")
    IO.puts("")
    one_shot(pid, prompt)
    IO.puts("")
  end

  defp run_tool_guardrail_demo(pid) do
    prompt =
      "Use the add_numbers tool to add 70 and 50. Do not do the math yourself. Reply with only the sum."

    IO.puts("Running imported-agent tool guardrail demo:")
    IO.puts("  #{prompt}")
    IO.puts("")
    one_shot(pid, prompt)
    IO.puts("")
  end

  defp one_shot(pid, prompt) do
    one_shot(pid, prompt, session: "imported-cli")
  end

  defp one_shot(pid, prompt, opts) when is_list(opts) do
    session = Keyword.get(opts, :session, "imported-cli")

    case Moto.chat(pid, prompt, context: %{"session" => session, "notify_pid" => self()}) do
      {:ok, reply} ->
        flush_interrupt_messages()
        IO.puts(reply)

      {:interrupt, interrupt} ->
        flush_interrupt_messages()
        IO.puts("interrupt: #{interrupt.kind} - #{interrupt.message}")

      {:error, reason} ->
        flush_interrupt_messages()
        IO.puts("error: #{inspect(reason)}")
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
            case Moto.chat(pid, prompt,
                   context: %{"session" => "imported-interactive", "notify_pid" => self()}
                 ) do
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
                flush_interrupt_messages()
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
end
