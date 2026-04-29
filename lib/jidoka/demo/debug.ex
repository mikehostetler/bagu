defmodule Jidoka.Demo.Debug do
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

  @row_width 12

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
    previous_debug_level = Jidoka.Runtime.debug()
    previous_logger_level = Logger.level()
    apply_log_level(level)

    try do
      fun.(level)
    after
      Jidoka.Runtime.debug(previous_debug_level)
      Logger.configure(level: previous_logger_level)
    end
  end

  @spec maybe_enable_agent_debug(pid(), log_level()) :: :ok
  def maybe_enable_agent_debug(pid, level) when is_pid(pid) and level in [:debug, :trace] do
    _ = Jidoka.Runtime.debug(pid)
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
    status = Jidoka.Runtime.debug_status()
    level = Map.get(status, :level, :unknown)
    overrides = Map.get(status, :overrides, %{})
    events = Map.get(overrides, :observe_debug_events, :default)
    telemetry = Map.get(overrides, :telemetry_log_level, :default)

    IO.puts("Debug status: runtime=#{level} events=#{events} telemetry=#{telemetry}")
    :ok
  end

  def print_trace_status(_level), do: :ok

  @spec request_log_level(log_level()) :: Logger.level()
  def request_log_level(_level), do: :warning

  @spec safe_stop_agent(pid()) :: :ok
  def safe_stop_agent(pid) when is_pid(pid) do
    case Jidoka.Runtime.stop_agent(pid) do
      :ok -> :ok
      {:error, :not_found} -> :ok
    end
  catch
    :exit, _reason -> :ok
  end

  @spec print_recent_events(pid(), log_level(), keyword()) :: :ok
  def print_recent_events(pid, level, opts \\ [])

  def print_recent_events(pid, :info, _opts) when is_pid(pid), do: :ok

  def print_recent_events(pid, level, opts) when is_pid(pid) and level in [:debug, :trace] do
    limit = Keyword.get(opts, :limit, 20)

    case Jidoka.Runtime.recent(pid, limit) do
      {:ok, []} ->
        section(debug_title(level))
        row("events", "none")

      {:ok, events} ->
        print_request_summary(pid, level, events)

      {:error, :debug_not_enabled} ->
        section(debug_title(level))
        row("events", "buffer unavailable")

      {:error, reason} ->
        section(debug_title(level))
        row("events", "failed: #{Jidoka.Error.format(reason)}")
    end

    IO.puts("")
    :ok
  end

  defp apply_log_level(:info) do
    Logger.configure(level: :warning)
    Jidoka.Runtime.debug(:off)
  end

  defp apply_log_level(:debug) do
    Logger.configure(level: :warning)
    Jidoka.Runtime.debug(:on)
  end

  defp apply_log_level(:trace) do
    Logger.configure(level: :warning)
    Jidoka.Runtime.debug(:verbose)
  end

  defp print_request_summary(pid, level, events) do
    case Jidoka.Debug.request_summary(pid) do
      {:ok, summary} ->
        section(debug_title(level))
        print_request_overview(summary)
        print_prompt_summary(summary, level)
        print_context_summary(summary, level)
        print_capability_summary(summary, level)
        print_memory_summary(summary.memory)
        print_subagent_summary(summary.subagents, level)
        print_workflow_summary(summary.workflows, level)
        print_usage_summary(summary)
        print_error_summary(summary)
        print_event_summary(events)
        print_structured_trace(pid, level)

      _ ->
        :ok
    end
  end

  defp print_request_overview(summary) do
    row("request", "#{summary.status || "unknown"} #{summary.request_id}")
    if summary.model, do: row("model", inspect(summary.model))
  end

  defp print_prompt_summary(summary, level) do
    cond do
      summary.user_message && summary.input_message &&
          summary.user_message != summary.input_message ->
        row("input", inspect(preview(summary.input_message, level)))
        row("prepared", inspect(preview(summary.user_message, level)))

      summary.user_message ->
        row("user", inspect(preview(summary.user_message, level)))

      true ->
        :ok
    end

    if level == :trace and summary.system_prompt do
      row("system", inspect(preview(summary.system_prompt, level)))
    end

    if level == :trace and is_integer(summary.message_count) do
      row("messages", Integer.to_string(summary.message_count))
    end
  end

  defp print_context_summary(%{context_preview: []}, _level), do: :ok

  defp print_context_summary(%{context_preview: items}, level) do
    public_items = Enum.reject(items, &String.starts_with?(&1, "domain="))
    hidden_count = length(items) - length(public_items)

    if public_items != [] or level == :trace do
      section("Context")
    end

    if public_items != [] do
      row("values", Enum.join(public_items, " "))
    end

    if level == :trace and hidden_count > 0 do
      row("internal", "#{hidden_count} hidden")
    end
  end

  defp print_capability_summary(summary, level) do
    tools = list_value(summary, :tool_names)
    skills = list_value(summary, :skills)
    mcp_tools = list_value(summary, :mcp_tools)
    mcp_errors = list_value(summary, :mcp_errors)
    mcp_count = count_mcp_proxy_tools(tools, mcp_tools)

    if tools != [] or skills != [] or mcp_tools != [] or mcp_errors != [] do
      section("Capabilities")

      if tools != [] do
        suffix = if mcp_count > 0, do: " (#{mcp_count} mcp)", else: ""
        row("tools", "#{length(tools)} available#{suffix}")

        if level == :trace do
          row("tool list", compact_list(tools, 12))
        end
      end

      if skills != [] do
        row("skills", Enum.join(skills, ", "))
      end

      if mcp_tools != [] do
        row("mcp", Enum.join(mcp_tools, ", "))
      end

      print_mcp_errors(mcp_errors, level)
    end
  end

  defp print_mcp_errors([], _level), do: :ok

  defp print_mcp_errors(errors, level) when is_list(errors) do
    Enum.each(errors, fn error ->
      endpoint = error[:endpoint] || "unknown"
      prefix = if error[:prefix], do: ":#{error.prefix}", else: ""
      reason = (error[:message] || Jidoka.Error.format(error[:reason])) |> preview(level)

      row("mcp error", "#{endpoint}#{prefix} #{reason}")
    end)
  end

  defp list_value(map, key) when is_map(map) do
    case Map.get(map, key, []) do
      values when is_list(values) -> values
      _other -> []
    end
  end

  defp print_memory_summary(%{error: reason}) do
    section("Memory")
    row("error", Jidoka.Error.format(reason))
  end

  defp print_memory_summary(%{} = memory) do
    if memory[:namespace] do
      section("Memory")
      inject = memory[:inject] || :none
      captured = Map.get(memory, :captured, false)
      row("namespace", memory.namespace)
      row("retrieved", to_string(memory.retrieved || 0))
      row("inject", to_string(inject))
      row("captured", to_string(captured))
      maybe_row("capture warning", memory[:capture_warning] || format_optional_error(memory[:capture_error]))
    else
      :ok
    end
  end

  defp print_memory_summary(_memory), do: :ok

  defp print_subagent_summary([], _level), do: :ok

  defp print_subagent_summary(calls, level) when is_list(calls) do
    section("Delegation")

    Enum.each(calls, fn call ->
      child = call[:child_id] || "ephemeral"
      duration = call[:duration_ms] || 0
      status = subagent_status(call)

      row(to_string(call.name), "#{status} #{duration}ms")

      if level == :trace do
        row("child", child)
        maybe_row("target", format_optional_term(call[:target]))
        maybe_row("forwarded", format_context_keys(call[:context_keys]))
        maybe_row("task", preview(call[:task_preview], level))
        maybe_row("result", preview(call[:result_preview], level))
      end
    end)
  end

  defp print_workflow_summary([], _level), do: :ok

  defp print_workflow_summary(calls, level) when is_list(calls) do
    section("Workflows")

    Enum.each(calls, fn call ->
      duration = call[:duration_ms] || 0
      status = workflow_status(call)

      row(to_string(call.name), "#{status} #{duration}ms")

      if level == :trace do
        maybe_row("workflow", format_optional_term(call[:workflow]))
        maybe_row("input", format_context_keys(call[:input_keys]))
        maybe_row("context", format_context_keys(call[:context_keys]))
        maybe_row("output", preview(call[:output_preview], level))
      end
    end)
  end

  defp print_usage_summary(%{usage: nil, duration_ms: nil}), do: :ok

  defp print_usage_summary(%{usage: nil, duration_ms: duration_ms}),
    do: print_duration(duration_ms)

  defp print_usage_summary(%{usage: usage, duration_ms: duration_ms}) do
    section("Usage")
    input = usage[:input] || "?"
    output = usage[:output] || "?"

    row("tokens", "input=#{input} output=#{output}")

    if usage[:cost] && usage[:cost] != 0 do
      row("cost", format_cost(usage[:cost]))
    end

    if duration_ms do
      row("duration", "#{duration_ms}ms")
    end
  end

  defp print_duration(duration_ms) do
    section("Usage")
    row("duration", "#{duration_ms}ms")
  end

  defp print_error_summary(%{interrupt: %{} = interrupt}) do
    section("Interrupt")
    row("kind", to_string(interrupt.kind))
    row("message", interrupt.message)
  end

  defp print_error_summary(%{error: {:guardrail, stage, label, reason}}) do
    section("Guardrail")
    row("stage", to_string(stage))
    row("name", to_string(label))
    row("reason", Jidoka.Error.format(reason))
  end

  defp print_error_summary(%{error: nil}), do: :ok

  defp print_error_summary(%{error: other}) do
    if match?({:interrupt, _}, other) do
      :ok
    else
      section("Error")
      row("reason", Jidoka.Error.format(other))
    end
  end

  defp print_event_summary(events) do
    summaries =
      events
      |> Enum.reverse()
      |> Enum.map(&summarize_event/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(&redundant_event?/1)
      |> Enum.uniq()

    case summaries do
      [] ->
        :ok

      entries ->
        section("Events")
        Enum.each(entries, fn entry -> row("event", entry) end)
    end
  end

  defp print_structured_trace(_pid, :debug), do: :ok

  defp print_structured_trace(pid, :trace) do
    case Jidoka.Trace.latest(pid) do
      {:ok, trace} ->
        section("Structured Trace")
        row("events", "#{length(trace.events)} status=#{trace.status || "unknown"}")
        row("categories", trace_categories(trace))

        trace.events
        |> Enum.take(-8)
        |> Enum.each(fn event ->
          row("trace", "#{event.category}.#{event.event} #{event.name || "-"} #{event.status || "-"}")
        end)

      {:error, _reason} ->
        :ok
    end
  end

  defp trace_categories(trace) do
    trace.events
    |> Enum.map(& &1.category)
    |> Enum.uniq()
    |> Enum.map(&Atom.to_string/1)
    |> Enum.join(", ")
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

  defp redundant_event?("model response received"), do: true
  defp redundant_event?("request completed"), do: true
  defp redundant_event?(_event), do: false

  defp subagent_status(%{outcome: :ok}), do: "ok"
  defp subagent_status(%{outcome: {:interrupt, _interrupt}}), do: "interrupt"
  defp subagent_status(%{outcome: {:error, reason}}), do: "error:#{Jidoka.Error.format(reason)}"
  defp subagent_status(call), do: get_in(call, [:child_result_meta, :status]) || "unknown"

  defp workflow_status(%{outcome: :ok}), do: "ok"
  defp workflow_status(%{outcome: {:error, reason}}), do: "error:#{Jidoka.Error.format(reason)}"
  defp workflow_status(_call), do: "unknown"

  defp invalid_log_level(level) do
    "invalid --log-level #{inspect(level)}. Expected one of: info, debug, trace"
  end

  defp debug_title(:trace), do: "Trace"
  defp debug_title(:debug), do: "Debug"

  defp preview(text, :trace), do: truncate(text, 240)
  defp preview(text, _level), do: truncate(text, 140)

  defp format_cost(nil), do: "?"
  defp format_cost(cost) when is_integer(cost), do: format_cost(cost / 1.0)
  defp format_cost(cost) when is_float(cost), do: :erlang.float_to_binary(cost, decimals: 6)
  defp format_cost(other), do: inspect(other)

  defp truncate(text, max_length) when is_binary(text) do
    if String.length(text) > max_length do
      String.slice(text, 0, max_length - 1) <> "…"
    else
      text
    end
  end

  defp truncate(nil, _max_length), do: nil
  defp truncate(other, max_length), do: other |> inspect() |> truncate(max_length)

  defp count_mcp_proxy_tools(tool_names, mcp_tools) do
    prefixes =
      mcp_tools
      |> Enum.map(&mcp_prefix/1)
      |> Enum.reject(&is_nil/1)

    Enum.count(tool_names, fn name ->
      Enum.any?(prefixes, &String.starts_with?(name, &1))
    end)
  end

  defp mcp_prefix(entry) do
    entry
    |> to_string()
    |> String.split(":", parts: 2)
    |> case do
      [_endpoint, prefix] when prefix != "" -> prefix
      _other -> nil
    end
  end

  defp compact_list(items, max) when length(items) <= max, do: Enum.join(items, ", ")

  defp compact_list(items, max) do
    {shown, hidden} = Enum.split(items, max)
    Enum.join(shown, ", ") <> " +" <> Integer.to_string(length(hidden)) <> " more"
  end

  defp format_context_keys(keys) when is_list(keys), do: Enum.join(keys, ", ")
  defp format_context_keys(_keys), do: nil

  defp format_optional_term(nil), do: nil
  defp format_optional_term(term), do: inspect(term)

  defp format_optional_error(nil), do: nil
  defp format_optional_error(error), do: Jidoka.Error.format(error)

  defp section(title) do
    IO.puts("")
    IO.puts(color(title, [:bright]))
  end

  defp row(label, value), do: IO.puts("  #{row_label(label)} #{value}")

  defp maybe_row(_label, nil), do: :ok
  defp maybe_row(_label, ""), do: :ok
  defp maybe_row(label, value), do: row(label, value)

  defp row_label(label) do
    label
    |> to_string()
    |> String.pad_trailing(@row_width)
    |> color([:faint])
  end

  defp color(text, codes) do
    if ansi?() do
      [IO.ANSI.format_fragment(codes, true), text, IO.ANSI.reset()] |> IO.iodata_to_binary()
    else
      text
    end
  end

  defp ansi? do
    IO.ANSI.enabled?() and System.get_env("NO_COLOR") in [nil, ""]
  end
end
