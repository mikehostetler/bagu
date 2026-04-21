defmodule Moto.Demo.ChatCLI do
  @moduledoc false

  alias Moto.Demo.{Debug, Loader}

  @switches [log_level: :string, dry_run: :boolean, help: :boolean]
  @aliases [l: :log_level]

  @spec main([String.t()]) :: :ok
  def main(argv) do
    Loader.load!(:chat)

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
    IO.puts("mix moto chat [--log-level info|debug|trace] [--dry-run] [prompt]")
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
      {:ok, pid} = agent_module().start_link(id: "script-chat-agent")
      Debug.maybe_enable_agent_debug(pid, log_level)

      try do
        if options.prompt == nil do
          interactive_loop(pid, log_level)
        else
          one_shot(pid, options.prompt, log_level)
        end
      after
        :ok = Moto.stop_agent(pid)
      end
    end
  end

  defp print_header(log_level) do
    chat_agent = agent_module()

    IO.puts("Moto chat demo")
    IO.puts("Resolved model: #{inspect(chat_agent.model())}")

    if log_level == :trace do
      IO.puts("Configured model: #{inspect(chat_agent.configured_model())}")
      IO.puts("Default context: #{inspect(chat_agent.context())}")
      IO.puts("Memory: #{inspect(chat_agent.memory())}")
      IO.puts("Skills: #{format_list(chat_agent.skill_names())}")
      IO.puts("MCP tools: #{inspect(chat_agent.mcp_tools())}")
      IO.puts("Plugins: #{Enum.join(chat_agent.plugin_names(), ", ")}")
      IO.puts("Tools: #{Enum.join(chat_agent.tool_names(), ", ")}")

      IO.puts(
        "Before-turn hooks: #{Enum.map_join(chat_agent.before_turn_hooks(), ", ", &inspect/1)}"
      )

      IO.puts(
        "After-turn hooks: #{Enum.map_join(chat_agent.after_turn_hooks(), ", ", &inspect/1)}"
      )

      IO.puts("Interrupt hooks: #{Enum.map_join(chat_agent.interrupt_hooks(), ", ", &inspect/1)}")

      IO.puts(
        "Input guardrails: #{Enum.map_join(chat_agent.input_guardrails(), ", ", &inspect/1)}"
      )

      IO.puts(
        "Output guardrails: #{Enum.map_join(chat_agent.output_guardrails(), ", ", &inspect/1)}"
      )

      IO.puts("Tool guardrails: #{Enum.map_join(chat_agent.tool_guardrails(), ", ", &inspect/1)}")
    end

    IO.puts("")
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
        IO.puts("agent> #{reply}")

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
                IO.puts("agent> #{reply}")
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

  defp join_prompt([]), do: nil
  defp join_prompt(args), do: Enum.join(args, " ")

  defp agent_module do
    Module.concat([Moto, Examples, Chat, Agents, ChatAgent])
  end

  defp format_list([]), do: "(none)"
  defp format_list(items), do: Enum.join(items, ", ")
end
