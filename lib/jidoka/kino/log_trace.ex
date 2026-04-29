defmodule Jidoka.Kino.LogTrace do
  @moduledoc false

  alias Jidoka.Kino.Render

  require Logger

  @spec trace(String.t(), (-> result), keyword()) :: result when result: term()
  def trace(label, fun, opts \\ []) when is_binary(label) and is_function(fun, 0) do
    handler_id = :"jidoka_kino_trace_#{System.unique_integer([:positive])}"
    previous_logger_level = Logger.level()
    previous_handler_levels = handler_levels()

    :ok =
      :logger.add_handler(handler_id, Jidoka.Kino.LoggerHandler, %{
        level: Keyword.get(opts, :level, :debug),
        config: %{collector: self()}
      })

    Logger.configure(level: Keyword.get(opts, :level, :debug))

    unless Keyword.get(opts, :show_raw_logs, false) do
      set_handler_levels(previous_handler_levels, Keyword.get(opts, :raw_log_level, :emergency))
    end

    try do
      result = fun.()
      flush_logs(Keyword.get(opts, :flush_ms, 100))
      events = drain_logs(Keyword.get(opts, :max_events, 200))
      render(label, events, opts)
      result
    after
      _ = :logger.remove_handler(handler_id)
      Logger.configure(level: previous_logger_level)
      restore_handler_levels(previous_handler_levels)
    end
  end

  defp handler_levels do
    :logger.get_handler_ids()
    |> Enum.map(fn handler_id ->
      {handler_id, handler_level(handler_id)}
    end)
  end

  defp handler_level(handler_id) do
    case :logger.get_handler_config(handler_id) do
      {:ok, %{level: level}} -> level
      _other -> nil
    end
  end

  defp set_handler_levels(handler_levels, level) do
    Enum.each(handler_levels, fn {handler_id, _previous_level} ->
      set_handler_level(handler_id, level)
    end)
  end

  defp restore_handler_levels(handler_levels) do
    Enum.each(handler_levels, fn
      {_handler_id, nil} -> :ok
      {handler_id, level} -> set_handler_level(handler_id, level)
    end)
  end

  defp set_handler_level(handler_id, level) do
    _ = :logger.set_handler_config(handler_id, :level, level)
    :ok
  end

  defp flush_logs(ms) do
    receive do
    after
      ms -> :ok
    end
  end

  defp drain_logs(max_events), do: drain_logs(max_events, [], 0)

  defp drain_logs(max_events, events, count) do
    receive do
      {:jidoka_kino_log, event} ->
        events = if count < max_events, do: [event | events], else: events
        drain_logs(max_events, events, count + 1)
    after
      25 -> Enum.reverse(events)
    end
  end

  defp render(label, events, opts) do
    rows = Enum.map(events, &event_row/1)

    Render.value("Runtime trace: #{label} (#{length(rows)} events)")

    if rows == [] do
      Render.value("No runtime events were captured for this call.")
    else
      render_table(label, rows, opts)
    end

    :ok
  end

  defp render_table(label, rows, opts) do
    rows =
      case Keyword.fetch(opts, :num_rows) do
        {:ok, num_rows} -> Enum.take(rows, num_rows)
        :error -> rows
      end

    Render.table(label, rows, keys: [:time, :level, :event, :source, :summary])
  end

  defp event_row(%{level: level, message: message, metadata: metadata}) do
    %{
      time: format_time(Map.get(metadata, :time)),
      level: level |> to_string() |> String.upcase(),
      event: event_name(message),
      source: event_source(message, metadata),
      summary: summarize(message)
    }
  end

  defp format_time(nil), do: ""

  defp format_time(time) when is_integer(time) do
    time
    |> DateTime.from_unix!(:microsecond)
    |> DateTime.to_time()
    |> Time.to_iso8601()
    |> String.slice(0, 12)
  rescue
    _error -> ""
  end

  defp event_name(message) do
    cond do
      String.contains?(message, "spawned child") -> "spawn child"
      String.starts_with?(message, "Executing ") -> "action"
      String.contains?(message, "Reasoning") -> "reasoning"
      true -> "log"
    end
  end

  defp event_source(message, metadata) do
    cond do
      match = Regex.run(~r/AgentServer ([^\s]+)/, message) ->
        Enum.at(match, 1)

      match = Regex.run(~r/Executing ([^\s]+) /, message) ->
        match |> Enum.at(1) |> short_module()

      mfa = Map.get(metadata, :mfa) ->
        format_mfa(mfa)

      pid = Map.get(metadata, :pid) ->
        inspect(pid)

      true ->
        ""
    end
  end

  defp summarize(message) do
    cond do
      match = Regex.run(~r/Executing ([^\s]+) with params: (.*)/s, message) ->
        module = match |> Enum.at(1) |> short_module()
        params = match |> Enum.at(2) |> Render.compact()
        Render.shorten("#{module} #{params}", 180)

      match = Regex.run(~r/AgentServer ([^\s]+) spawned child ([^\s]+)/, message) ->
        "#{Enum.at(match, 1)} -> #{Enum.at(match, 2)}"

      true ->
        message |> Render.compact() |> Render.shorten(180)
    end
  end

  defp short_module(module) do
    module
    |> String.split(".")
    |> Enum.take(-2)
    |> Enum.join(".")
  end

  defp format_mfa({module, function, arity}), do: "#{inspect(module)}.#{function}/#{arity}"
  defp format_mfa(other), do: inspect(other)
end
