defmodule Jidoka.Demo.AgentSession do
  @moduledoc false

  alias Jidoka.Demo.{Debug, Markdown}

  @type mode :: :one_shot | :interactive
  @type chat_result ::
          {:ok, term()} | {:interrupt, Jidoka.Interrupt.t()} | {:handoff, Jidoka.Handoff.t()} | {:error, term()}
  @type chat_fun :: (pid(), String.t(), Debug.log_level(), mode() -> chat_result())

  @spec one_shot(pid(), String.t(), Debug.log_level(), keyword()) :: :ok
  def one_shot(pid, prompt, log_level, opts) when is_pid(pid) and is_binary(prompt) do
    run_prompt(pid, prompt, log_level, :one_shot, opts)
  end

  @spec interactive_loop(pid(), Debug.log_level(), keyword()) :: :ok
  def interactive_loop(pid, log_level, opts) when is_pid(pid) do
    opts
    |> Keyword.get(:intro, "Type `exit` or press Ctrl-D to quit.")
    |> IO.puts()

    opts
    |> Keyword.get(:try, [])
    |> Enum.each(&IO.puts("Try: #{&1}"))

    IO.puts("")
    loop(pid, log_level, opts)
  end

  defp loop(pid, log_level, opts) do
    case IO.gets("you> ") do
      :eof ->
        :ok

      {:error, _reason} ->
        :ok

      input ->
        prompt = String.trim(input)

        cond do
          prompt == "" ->
            loop(pid, log_level, opts)

          prompt in ["exit", "quit"] ->
            :ok

          true ->
            IO.puts("")
            run_prompt(pid, prompt, log_level, :interactive, opts)
            IO.puts("")
            loop(pid, log_level, opts)
        end
    end
  end

  defp run_prompt(pid, prompt, log_level, mode, opts) do
    chat_fun = Keyword.fetch!(opts, :chat)
    result = chat_fun.(pid, prompt, log_level, mode)

    print_result(result, pid, log_level, mode, opts)
  end

  defp print_result({:ok, reply}, pid, log_level, mode, opts) do
    flush_interrupts(opts)
    print_subagent_calls(pid, log_level, Keyword.get(opts, :subagents, false))
    Debug.print_recent_events(pid, log_level)
    Markdown.print_reply(reply_label(mode, opts), reply)
  end

  defp print_result({:interrupt, interrupt}, pid, log_level, _mode, opts) do
    flush_interrupts(opts)
    print_subagent_calls(pid, log_level, Keyword.get(opts, :subagents, false))
    Debug.print_recent_events(pid, log_level)
    IO.puts("interrupt> #{interrupt.kind} - #{interrupt.message}")
  end

  defp print_result({:handoff, handoff}, pid, log_level, _mode, opts) do
    flush_interrupts(opts)
    print_subagent_calls(pid, log_level, Keyword.get(opts, :subagents, false))
    Debug.print_recent_events(pid, log_level)

    IO.puts("handoff> #{handoff.name} conversation=#{handoff.conversation_id} owner=#{handoff.to_agent_id}")

    if handoff.summary, do: IO.puts("handoff> summary=#{handoff.summary}")
    if handoff.reason, do: IO.puts("handoff> reason=#{handoff.reason}")
  end

  defp print_result({:error, reason}, pid, log_level, _mode, opts) do
    flush_interrupts(opts)
    print_subagent_calls(pid, log_level, Keyword.get(opts, :subagents, false))
    Debug.print_recent_events(pid, log_level)
    IO.puts("error> #{Jidoka.Error.format(reason)}")
  end

  defp reply_label(:interactive, opts) do
    Keyword.get(opts, :interactive_reply_label, Keyword.get(opts, :reply_label, "agent"))
  end

  defp reply_label(:one_shot, opts), do: Keyword.get(opts, :reply_label, "agent")

  defp flush_interrupts(opts) do
    case Keyword.get(opts, :interrupts) do
      nil ->
        :ok

      tag when is_atom(tag) ->
        flush_interrupt_tag(tag, &default_interrupt_message/1)

      {tag, formatter} when is_atom(tag) and is_function(formatter, 1) ->
        flush_interrupt_tag(tag, formatter)
    end
  end

  defp flush_interrupt_tag(tag, formatter) do
    receive do
      {^tag, interrupt} ->
        interrupt
        |> formatter.()
        |> IO.puts()

        flush_interrupt_tag(tag, formatter)
    after
      0 -> :ok
    end
  end

  defp default_interrupt_message(%{kind: kind, message: message, data: data}) do
    tenant =
      if is_map(data) do
        Map.get(data, :tenant) || Map.get(data, "tenant")
      end

    suffix = if tenant, do: " tenant=#{tenant}", else: ""
    "hook> on_interrupt received #{kind}#{suffix}: #{message}"
  end

  defp print_subagent_calls(_pid, _level, false), do: :ok
  defp print_subagent_calls(_pid, _level, nil), do: :ok
  defp print_subagent_calls(_pid, level, _opts) when level in [:debug, :trace], do: :ok

  defp print_subagent_calls(pid, :info, opts) do
    opts = normalize_subagent_opts(opts)

    case Jidoka.Subagent.latest_request_calls(pid) do
      [] ->
        if opts.empty == :print, do: IO.puts("delegation> none")

      entries ->
        Enum.each(entries, fn entry ->
          IO.puts(format_subagent_call(entry, opts))
        end)
    end
  end

  defp normalize_subagent_opts(true), do: %{empty: :silent, result_preview?: false}
  defp normalize_subagent_opts(opts) when is_list(opts), do: Map.merge(normalize_subagent_opts(true), Map.new(opts))

  defp format_subagent_call(entry, opts) do
    line =
      "delegation> #{entry.name} mode=#{entry.mode} child=#{entry.child_id || "ephemeral"} " <>
        "status=#{subagent_status(entry)} duration_ms=#{entry[:duration_ms] || 0}"

    result = entry[:result_preview]

    if opts.result_preview? and is_binary(result) and result != "" do
      line <> " result=#{inspect(result)}"
    else
      line
    end
  end

  defp subagent_status(%{outcome: :ok}), do: "ok"
  defp subagent_status(%{outcome: {:interrupt, _interrupt}}), do: "interrupt"
  defp subagent_status(%{outcome: {:error, reason}}), do: "error:#{Jidoka.Error.format(reason)}"
  defp subagent_status(entry), do: get_in(entry, [:child_result_meta, :status]) || "unknown"
end
