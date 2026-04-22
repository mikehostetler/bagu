defmodule Moto.Demo.ImportedChatCLI do
  @moduledoc false

  alias Moto.Demo.{CLI, Debug, Inventory, Markdown}

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
  def usage, do: CLI.usage("imported")

  defp run(options, log_level) do
    spec_path = sample_spec_path()
    available_tools = [AddNumbers]
    available_hooks = [ReplyWithFinalAnswer]
    available_guardrails = [BlockSecretPrompt, BlockUnsafeReply, ApproveLargeMathTool]
    available_skills = []
    {:ok, tool_registry} = Moto.Tool.normalize_available_tools(available_tools)
    {:ok, hook_registry} = Moto.Hook.normalize_available_hooks(available_hooks)

    {:ok, guardrail_registry} =
      Moto.Guardrail.normalize_available_guardrails(available_guardrails)

    Logger.configure(level: :error)

    agent =
      Moto.import_agent_file!(spec_path,
        available_tools: available_tools,
        available_skills: available_skills,
        available_hooks: available_hooks,
        available_guardrails: available_guardrails
      )

    Inventory.print_imported("Moto imported-agent demo", agent, log_level,
      source: spec_path,
      registries: %{
        tools: Map.keys(tool_registry),
        skills: [],
        hooks: Map.keys(hook_registry),
        guardrails: Map.keys(guardrail_registry)
      },
      try: [
        ~s(mix moto imported -- "Use the add_numbers tool to add 17 and 25. Reply with only the sum."),
        ~s(mix moto imported --log-level trace -- "Use the add_numbers tool to add 8 and 13.")
      ]
    )

    CLI.print_log_status(log_level)

    CLI.with_started_agent(
      options,
      log_level,
      fn -> Moto.start_agent(agent, id: "imported-script-chat-agent") end,
      &interactive_loop/2,
      &one_shot/3
    )
  end

  defp sample_spec_path do
    Path.expand("../../../examples/chat/imported/sample_math_agent.json", __DIR__)
  end

  defp one_shot(pid, prompt, log_level) do
    one_shot(pid, prompt, log_level, session: "imported-cli")
  end

  defp one_shot(pid, prompt, log_level, opts) when is_list(opts) do
    session = Keyword.get(opts, :session, "imported-cli")

    case Moto.chat(pid, prompt,
           context: %{"session" => session, "notify_pid" => self()},
           log_level: Debug.request_log_level(log_level)
         ) do
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
    IO.puts("Enter a prompt. Type `exit` or press Ctrl-D to quit.")
    IO.puts("Try: Add 8 and 13.")
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
            case Moto.chat(pid, prompt,
                   context: %{"session" => "imported-interactive", "notify_pid" => self()},
                   log_level: Debug.request_log_level(log_level)
                 ) do
              {:ok, reply} ->
                flush_interrupt_messages()
                IO.puts("")
                Debug.print_recent_events(pid, log_level)
                Markdown.print_reply("claude", reply)
                IO.puts("")
                loop(pid, log_level)

              {:interrupt, interrupt} ->
                flush_interrupt_messages()
                IO.puts("")
                Debug.print_recent_events(pid, log_level)
                IO.puts("interrupt> #{interrupt.kind} - #{interrupt.message}")
                IO.puts("")
                loop(pid, log_level)

              {:error, reason} ->
                flush_interrupt_messages()
                IO.puts("")
                Debug.print_recent_events(pid, log_level)
                IO.puts("error> #{inspect(reason)}")
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
end
