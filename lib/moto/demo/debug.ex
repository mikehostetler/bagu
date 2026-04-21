defmodule Moto.Demo.Debug do
  @moduledoc false

  require Logger

  @type log_level :: :info | :debug | :trace

  @signal_summaries %{
    "ai.request.started" => "request started",
    "ai.request.completed" => "request completed",
    "ai.request.failed" => "request failed",
    "ai.llm.response" => "model response received",
    "ai.tool.started" => "tool called",
    "ai.tool.result" => "tool finished"
  }

  @spec parse_log_level(keyword()) :: {:ok, log_level()} | {:error, String.t()}
  def parse_log_level(opts) when is_list(opts) do
    case Keyword.get(opts, :log_level, "info") do
      level when level in [:info, :debug, :trace] ->
        {:ok, level}

      level when is_binary(level) ->
        level
        |> String.trim()
        |> String.downcase()
        |> case do
          "info" -> {:ok, :info}
          "debug" -> {:ok, :debug}
          "trace" -> {:ok, :trace}
          other -> {:error, invalid_log_level(other)}
        end

      other ->
        {:error, invalid_log_level(other)}
    end
  end

  @spec with_log_level(log_level(), (log_level() -> term())) :: term()
  def with_log_level(level, fun) when level in [:info, :debug, :trace] and is_function(fun, 1) do
    previous_debug_level = Moto.Runtime.debug()
    previous_logger_level = Logger.level()
    apply_log_level(level)

    try do
      fun.(level)
    after
      Moto.Runtime.debug(previous_debug_level)
      Logger.configure(level: previous_logger_level)
    end
  end

  @spec maybe_enable_agent_debug(pid(), log_level()) :: :ok
  def maybe_enable_agent_debug(pid, level) when is_pid(pid) and level in [:debug, :trace] do
    _ = Moto.Runtime.debug(pid)
    :ok
  end

  def maybe_enable_agent_debug(_pid, :info), do: :ok

  @spec print_status(log_level()) :: :ok
  def print_status(level) when level in [:info, :debug, :trace] do
    IO.puts("Log level: #{level}")
    :ok
  end

  @spec print_trace_status(log_level()) :: :ok
  def print_trace_status(:trace) do
    IO.puts("Debug status: #{inspect(Moto.Runtime.debug_status())}")
    :ok
  end

  def print_trace_status(_level), do: :ok

  @spec request_log_level(log_level()) :: Logger.level()
  def request_log_level(_level), do: :warning

  @spec print_recent_events(pid(), log_level(), keyword()) :: :ok
  def print_recent_events(pid, level, opts \\ [])

  def print_recent_events(pid, :info, _opts) when is_pid(pid), do: :ok

  def print_recent_events(pid, level, opts) when is_pid(pid) and level in [:debug, :trace] do
    limit = Keyword.get(opts, :limit, 20)

    case Moto.Runtime.recent(pid, limit) do
      {:ok, []} ->
        IO.puts("debug> no recent events")

      {:ok, events} ->
        print_request_summary(pid, level)
        print_event_summary(events)
        maybe_print_raw_events(events, level)

      {:error, :debug_not_enabled} ->
        IO.puts("debug> event buffer unavailable")

      {:error, reason} ->
        IO.puts("debug> failed to fetch recent events: #{inspect(reason)}")
    end

    :ok
  end

  defp apply_log_level(:info) do
    Logger.configure(level: :warning)
    Moto.Runtime.debug(:off)
  end

  defp apply_log_level(:debug) do
    Logger.configure(level: :warning)
    Moto.Runtime.debug(:on)
  end

  defp apply_log_level(:trace) do
    Logger.configure(level: :warning)
    Moto.Runtime.debug(:verbose)
  end

  defp print_request_summary(pid, level) do
    case Moto.Debug.request_summary(pid) do
      {:ok, summary} ->
        IO.puts("debug> request #{summary.request_id} status=#{summary.status}")
        maybe_print_model(summary)
        maybe_print_prompt_summary(summary, level)
        maybe_print_skill_summary(summary)
        maybe_print_tool_summary(summary)
        maybe_print_mcp_summary(summary)
        maybe_print_context_keys(summary, level)
        maybe_print_memory_summary(summary.memory)
        maybe_print_subagent_summary(summary.subagents, level)
        maybe_print_usage_summary(summary)
        maybe_print_error_summary(summary)

      _ ->
        :ok
    end
  end

  defp maybe_print_model(%{model: nil}), do: :ok

  defp maybe_print_model(%{model: model}) do
    IO.puts("debug> model #{inspect(model)}")
  end

  defp maybe_print_prompt_summary(summary, level) do
    cond do
      summary.user_message && summary.input_message &&
          summary.user_message != summary.input_message ->
        IO.puts("debug> input #{inspect(preview(summary.input_message, level))}")
        IO.puts("debug> prepared user #{inspect(preview(summary.user_message, level))}")

      summary.user_message ->
        IO.puts("debug> user #{inspect(preview(summary.user_message, level))}")

      true ->
        :ok
    end

    if summary.system_prompt do
      IO.puts("debug> system #{inspect(preview(summary.system_prompt, level))}")
    end

    if level == :trace and is_integer(summary.message_count) do
      IO.puts("debug> messages count=#{summary.message_count}")
    end
  end

  defp maybe_print_tool_summary(%{tool_names: []}), do: :ok

  defp maybe_print_tool_summary(%{tool_names: tool_names}) do
    IO.puts("debug> tools #{Enum.join(tool_names, ", ")}")
  end

  defp maybe_print_skill_summary(%{skills: []}), do: :ok

  defp maybe_print_skill_summary(%{skills: skills}) do
    IO.puts("debug> skills #{Enum.join(skills, ", ")}")
  end

  defp maybe_print_mcp_summary(%{mcp_tools: []}), do: :ok

  defp maybe_print_mcp_summary(%{mcp_tools: mcp_tools}) do
    IO.puts("debug> mcp #{Enum.join(mcp_tools, ", ")}")
  end

  defp maybe_print_context_keys(%{context_preview: []}, _level), do: :ok

  defp maybe_print_context_keys(%{context_preview: items}, _level) do
    IO.puts("debug> context #{Enum.join(items, " ")}")
  end

  defp maybe_print_memory_summary(%{error: reason}) do
    IO.puts("debug> memory error=#{inspect(reason)}")
  end

  defp maybe_print_memory_summary(%{} = memory) do
    if memory[:namespace] do
      inject = memory[:inject] || :none
      captured = Map.get(memory, :captured, false)

      IO.puts(
        "debug> memory namespace=#{memory.namespace} retrieved=#{memory.retrieved} inject=#{inject} captured=#{captured}"
      )
    else
      :ok
    end
  end

  defp maybe_print_memory_summary(_memory), do: :ok

  defp maybe_print_subagent_summary([], _level), do: :ok

  defp maybe_print_subagent_summary(calls, level) when is_list(calls) do
    Enum.each(calls, fn call ->
      child = call[:child_id] || "ephemeral"
      duration = call[:duration_ms] || 0
      child_status = get_in(call, [:child_result_meta, :status]) || "unknown"

      summary =
        "debug> delegated to #{call.name} mode=#{call.mode} child=#{child} child_status=#{child_status} duration_ms=#{duration}"

      if level == :trace and is_binary(call[:task_preview]) and call.task_preview != "" do
        IO.puts(summary <> " task=" <> inspect(preview(call.task_preview, level)))
      else
        IO.puts(summary)
      end
    end)
  end

  defp maybe_print_usage_summary(%{usage: nil}), do: :ok

  defp maybe_print_usage_summary(%{usage: usage, duration_ms: duration_ms}) do
    input = usage[:input] || "?"
    output = usage[:output] || "?"
    cost = format_cost(usage[:cost])

    IO.puts(
      "debug> usage input=#{input} output=#{output} cost=#{cost} duration_ms=#{duration_ms || "?"}"
    )
  end

  defp maybe_print_error_summary(%{interrupt: %{} = interrupt}) do
    IO.puts("debug> interrupt kind=#{interrupt.kind} message=#{interrupt.message}")
  end

  defp maybe_print_error_summary(%{error: {:guardrail, stage, label, reason}}) do
    IO.puts("debug> guardrail blocked stage=#{stage} name=#{label} reason=#{inspect(reason)}")
  end

  defp maybe_print_error_summary(%{error: nil}), do: :ok

  defp maybe_print_error_summary(%{error: other}) do
    if match?({:interrupt, _}, other) do
      :ok
    else
      IO.puts("debug> error #{inspect(other)}")
    end
  end

  defp print_event_summary(events) do
    summaries =
      events
      |> Enum.reverse()
      |> Enum.map(&summarize_event/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    case summaries do
      [] ->
        :ok

      entries ->
        Enum.each(entries, fn entry -> IO.puts("debug> #{entry}") end)
    end
  end

  defp summarize_event(%{data: data}) when is_map(data) do
    signal_type =
      Map.get(data, :type) ||
        Map.get(data, "type") ||
        Map.get(data, :signal_type) ||
        Map.get(data, "signal_type")

    tool_name =
      Map.get(data, :tool_name) ||
        Map.get(data, "tool_name") ||
        "unknown"

    case Map.get(@signal_summaries, signal_type) do
      "tool started" ->
        format_tool_signal("tool started", tool_name)

      "tool finished" ->
        format_tool_signal("tool finished", tool_name)

      nil ->
        nil

      message ->
        message
    end
  end

  defp summarize_event(_event), do: nil

  defp format_tool_signal(message, "unknown"), do: message
  defp format_tool_signal(message, tool_name), do: "#{message} name=#{tool_name}"

  defp maybe_print_raw_events(events, :trace) do
    interesting =
      events
      |> Enum.reverse()
      |> Enum.filter(&interesting_event?/1)

    if interesting != [] do
      IO.puts("debug> recent events")

      Enum.each(interesting, fn event ->
        IO.puts("debug> #{event.type} #{format_event_data(event.data, :trace)}")
      end)
    end
  end

  defp maybe_print_raw_events(_events, _level), do: :ok

  defp invalid_log_level(level) do
    "invalid --log-level #{inspect(level)}. Expected one of: info, debug, trace"
  end

  defp preview(text, :trace), do: truncate(text, 240)
  defp preview(text, _level), do: truncate(text, 140)

  defp format_cost(nil), do: "?"
  defp format_cost(cost) when is_integer(cost), do: format_cost(cost / 1.0)
  defp format_cost(cost) when is_float(cost), do: :erlang.float_to_binary(cost, decimals: 6)
  defp format_cost(other), do: inspect(other)

  defp interesting_event?(%{data: data}) when is_map(data) do
    signal_type =
      Map.get(data, :type) ||
        Map.get(data, "type") ||
        Map.get(data, :signal_type) ||
        Map.get(data, "signal_type")

    signal_type in Map.keys(@signal_summaries)
  end

  defp interesting_event?(_event), do: false

  defp truncate(text, max_length) when is_binary(text) do
    if String.length(text) > max_length do
      String.slice(text, 0, max_length - 1) <> "…"
    else
      text
    end
  end

  defp format_event_data(data, :trace) when is_map(data) do
    inspect(data, pretty: true, limit: :infinity)
  end

  defp format_event_data(data, _level) when is_map(data) do
    data
    |> Map.take([:type, :id, :signal_type, :directive_type, :tool_name, :request_id, :call_id])
    |> case do
      summary when map_size(summary) == 0 ->
        "keys=#{inspect(Map.keys(data))}"

      summary ->
        inspect(summary)
    end
  end

  defp format_event_data(data, _level), do: inspect(data)
end
