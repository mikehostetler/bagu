defmodule Moto.Demo.ImportedChatCLI do
  @moduledoc false

  alias Moto.Demo.Debug
  alias Moto.ImportedAgent

  alias Moto.Examples.Chat.Guardrails.{
    ApproveLargeMathTool,
    BlockSecretPrompt,
    BlockUnsafeReply
  }

  alias Moto.Examples.Chat.Hooks.ReplyWithFinalAnswer
  alias Moto.Examples.Chat.Tools.AddNumbers
  require Logger

  @switches [log_level: :string, dry_run: :boolean, help: :boolean]
  @aliases [l: :log_level]

  @spec main([String.t()]) :: :ok | no_return()
  def main(argv) do
    Moto.Demo.Loader.load!(:chat)

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
    IO.puts("mix moto imported [--log-level info|debug|trace] [--dry-run] [prompt]")
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
             prompt: join_prompt(normalize_argv(args))
           }}
        end
    end
  end

  defp run(options, log_level) do
    anthropic_api_key = Application.get_env(:req_llm, :anthropic_api_key)
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

    IO.puts("Moto imported-agent demo")
    IO.puts("Resolved model: #{inspect(Moto.model(:fast))}")

    if log_level == :trace do
      IO.puts("Spec file: #{spec_path}")
      IO.puts("Available tools: #{Enum.join(Map.keys(tool_registry), ", ")}")
      IO.puts("Available skills: #{format_name_list(Map.keys(%{}))}")
      IO.puts("Available hooks: #{Enum.join(Map.keys(hook_registry), ", ")}")
      IO.puts("Available guardrails: #{Enum.join(Map.keys(guardrail_registry), ", ")}")
    end

    IO.puts("")
    Debug.print_status(log_level)
    Debug.print_trace_status(log_level)

    if options.dry_run? do
      IO.puts("Dry run: no agent started.")
      :ok
    else
      if is_nil(anthropic_api_key) or anthropic_api_key == "" do
        IO.puts("ANTHROPIC_API_KEY is not configured.")
        IO.puts("Add it to .env or export it in your shell.")
        System.halt(1)
      end

      agent =
        Moto.import_agent_file!(spec_path,
          available_tools: available_tools,
          available_skills: available_skills,
          available_hooks: available_hooks,
          available_guardrails: available_guardrails
        )

      if log_level == :trace do
        print_agent_details(agent)
      end

      {:ok, pid} = Moto.start_agent(agent, id: "imported-script-chat-agent")
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

  defp sample_spec_path do
    Path.expand("../../../examples/chat/imported/sample_math_agent.json", __DIR__)
  end

  defp print_agent_details(%ImportedAgent{
         spec: spec,
         tool_modules: tool_modules,
         skill_refs: skill_refs,
         mcp_tools: mcp_tools,
         hook_modules: hook_modules,
         guardrail_modules: guardrail_modules
       }) do
    IO.puts("Imported agent: #{spec.name}")
    IO.puts("Configured model: #{inspect(spec.model)}")
    IO.puts("Resolved model: #{inspect(Moto.model(spec.model))}")
    IO.puts("Default context: #{inspect(spec.context)}")
    IO.puts("Memory: #{inspect(spec.memory)}")
    IO.puts("Imported skills: #{format_name_list(spec.skills)}")
    IO.puts("Skill paths: #{format_name_list(spec.skill_paths)}")
    IO.puts("Resolved skill refs: #{format_skill_refs(skill_refs)}")
    IO.puts("MCP tools: #{inspect(mcp_tools)}")
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

  defp join_prompt([]), do: nil
  defp join_prompt(args), do: Enum.join(args, " ")

  defp format_name_list([]), do: "(none)"
  defp format_name_list(items), do: Enum.join(items, ", ")

  defp format_skill_refs([]), do: "(none)"

  defp format_skill_refs(refs) do
    Enum.map_join(refs, ", ", fn
      module when is_atom(module) -> inspect(module)
      name when is_binary(name) -> name
    end)
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
                IO.puts("claude> #{reply}")
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
