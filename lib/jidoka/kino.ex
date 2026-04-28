defmodule Jidoka.Kino.LoggerHandler do
  @moduledoc """
  Internal logger handler used by `Jidoka.Kino.trace/3`.

  The handler forwards formatted runtime log messages back to the Livebook cell
  process that installed it.
  """

  @doc "Accepts the logger handler configuration unchanged."
  @spec adding_handler(term()) :: {:ok, term()}
  def adding_handler(config), do: {:ok, config}

  @doc "Acknowledges removal of the temporary logger handler."
  @spec removing_handler(term()) :: :ok
  def removing_handler(_config), do: :ok

  @doc "Accepts logger handler configuration updates unchanged."
  @spec changing_config(term(), term(), term()) :: {:ok, term()}
  def changing_config(_set_or_update, _old_config, new_config), do: {:ok, new_config}

  @doc "Returns the active logger filter configuration unchanged."
  @spec filter_config(term()) :: term()
  def filter_config(config), do: config

  @doc "Forwards one logger event to the configured collector process."
  @spec log(map(), map()) :: term()
  def log(%{level: level, msg: message, meta: metadata}, %{config: %{collector: collector}}) do
    send(collector, {:jidoka_kino_log, %{level: level, message: format_message(message), metadata: metadata}})
  end

  defp format_message({:string, message}), do: to_string(message)
  defp format_message({:report, report}), do: inspect(report, pretty: true, limit: 50)

  defp format_message({:format, format, args}) do
    format
    |> :io_lib.format(args)
    |> IO.iodata_to_binary()
  rescue
    _error -> inspect({format, args}, limit: 50)
  end

  defp format_message(message), do: inspect(message, limit: 50)
end

defmodule Jidoka.Kino do
  @moduledoc """
  Small Livebook helpers for Jidoka examples.

  `Jidoka.Kino` keeps notebook cells focused on the agent code. It configures
  quiet runtime logs, mirrors Livebook secrets into the provider environment,
  captures useful Jido/Jidoka log events, and renders those events with Kino
  when Kino is available.

  Kino is intentionally optional. This module compiles and runs without Kino;
  rendering becomes a no-op outside Livebook.
  """

  require Logger

  @provider_env_names ["ANTHROPIC_API_KEY", "LB_ANTHROPIC_API_KEY"]

  @doc """
  Configures the notebook runtime for concise Jidoka output.

  By default, raw runtime logs are quiet and provider-backed examples can rely
  on a Livebook secret named `ANTHROPIC_API_KEY`.
  """
  @spec setup(keyword()) :: :ok
  def setup(opts \\ []) do
    show_raw_logs? = Keyword.get(opts, :show_raw_logs, false)
    log_level = if(show_raw_logs?, do: :notice, else: :warning)

    Logger.configure(level: log_level)
    Jidoka.Runtime.debug(if(show_raw_logs?, do: :on, else: :off))
    _ = load_provider_env(Keyword.get(opts, :provider_env, @provider_env_names))

    :ok
  end

  @doc """
  Starts a Jidoka agent unless an agent with `id` is already running.

  This keeps Livebook cells repeatable. `start_fun` should be a zero-arity
  function that returns the normal `{:ok, pid}` agent start result.
  """
  @spec start_or_reuse(String.t(), (-> {:ok, pid()} | {:error, term()})) ::
          {:ok, pid()} | {:error, term()}
  def start_or_reuse(id, start_fun) when is_binary(id) and is_function(start_fun, 0) do
    case Jidoka.whereis(id) do
      nil -> start_fun.()
      pid -> {:ok, pid}
    end
  end

  @doc """
  Copies a Livebook provider secret into the environment name expected by ReqLLM.

  The default lookup accepts either `ANTHROPIC_API_KEY` or Livebook's
  `LB_ANTHROPIC_API_KEY`.
  """
  @spec load_provider_env([String.t()]) :: {:ok, String.t()} | {:error, String.t()}
  def load_provider_env(names \\ @provider_env_names) when is_list(names) do
    case find_env(names) do
      nil ->
        clear_empty_env("ANTHROPIC_API_KEY")
        {:error, "Set ANTHROPIC_API_KEY, or a Livebook secret named ANTHROPIC_API_KEY"}

      {"ANTHROPIC_API_KEY", _key} ->
        {:ok, "ANTHROPIC_API_KEY"}

      {name, key} ->
        System.put_env("ANTHROPIC_API_KEY", key)
        {:ok, name}
    end
  end

  @doc """
  Captures runtime log events around `fun` and renders a compact trace table.
  """
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

  @doc """
  Captures a provider-backed chat call and returns plain extracted text.
  """
  @spec chat(String.t(), (-> term()), keyword()) :: term()
  def chat(label, fun, opts \\ []) when is_binary(label) and is_function(fun, 0) do
    with {:ok, _source} <- load_provider_env(Keyword.get(opts, :provider_env, @provider_env_names)) do
      result =
        label
        |> trace(fun, opts)
        |> format_chat_result()

      if Keyword.get(opts, :render_result?, true) do
        render_chat_result(label, result)
      end

      result
    end
  end

  @doc """
  Formats common Jidoka chat results for notebook output.
  """
  @spec format_chat_result(term()) :: term()
  def format_chat_result({:ok, turn}), do: {:ok, extract_turn_text(turn)}
  def format_chat_result({:handoff, %Jidoka.Handoff{} = handoff}), do: {:handoff, handoff_summary(handoff)}
  def format_chat_result({:interrupt, %Jidoka.Interrupt{} = interrupt}), do: {:interrupt, interrupt_summary(interrupt)}
  def format_chat_result({:error, {:handoff, %Jidoka.Handoff{} = handoff}}), do: {:handoff, handoff_summary(handoff)}

  def format_chat_result({:error, {:interrupt, %Jidoka.Interrupt{} = interrupt}}),
    do: {:interrupt, interrupt_summary(interrupt)}

  def format_chat_result({:error, reason}), do: {:error, Jidoka.format_error(reason)}
  def format_chat_result(other), do: other

  @doc """
  Renders a runtime context map with public and internal keys separated.
  """
  @spec context(String.t(), map(), keyword()) :: :ok
  def context(label, context, opts \\ []) when is_binary(label) and is_map(context) do
    context
    |> Enum.map(fn {key, value} ->
      %{
        visibility: context_visibility(key),
        key: format_context_key(key),
        type: value_type(value),
        preview: inspect_value(value, Keyword.get(opts, :limit, 25))
      }
    end)
    |> Enum.sort_by(fn row -> {visibility_order(row.visibility), row.key} end)
    |> then(&table(label, &1, keys: [:visibility, :key, :type, :preview]))
  end

  @doc """
  Renders Jidoka's inspection summary for an agent definition or running agent.
  """
  @spec debug_agent(module() | struct() | pid() | String.t() | map(), keyword()) :: {:ok, map()} | {:error, String.t()}
  def debug_agent(target, opts \\ []) do
    case inspect_agent_target(target) do
      {:ok, inspection} ->
        render_agent_debug(inspection, opts)
        {:ok, inspection}

      {:error, reason} ->
        message = Jidoka.format_error(reason)
        render_markdown("### Agent Debug\n\n#{escape_markdown(message)}")
        {:error, message}
    end
  end

  @doc """
  Renders a Mermaid diagram of an agent's model, context, lifecycle, and tools.
  """
  @spec agent_diagram(module() | struct() | pid() | String.t() | map(), keyword()) ::
          {:ok, String.t()} | {:error, String.t()}
  def agent_diagram(target, opts \\ []) do
    case inspect_agent_target(target) do
      {:ok, inspection} ->
        markdown = build_agent_diagram(inspection, opts)
        render_markdown(markdown)
        {:ok, markdown}

      {:error, reason} ->
        message = Jidoka.format_error(reason)
        render_markdown("### Agent Diagram\n\n#{escape_markdown(message)}")
        {:error, message}
    end
  end

  @doc """
  Renders the latest structured Jidoka trace as a compact timeline.
  """
  @spec timeline(Jidoka.Trace.t() | pid() | String.t() | Jido.Agent.t(), keyword()) ::
          {:ok, Jidoka.Trace.t()} | {:error, String.t()}
  def timeline(target, opts \\ []) do
    case resolve_trace_target(target, opts) do
      {:ok, trace} ->
        rows = Enum.map(trace.events, &timeline_row/1)
        table("Trace timeline", rows, keys: [:seq, :time, :source, :event, :name, :status, :duration_ms])
        {:ok, trace}

      {:error, reason} ->
        message = Jidoka.format_error(reason)
        render_markdown("### Trace Timeline\n\n#{escape_markdown(message)}")
        {:error, message}
    end
  end

  @doc """
  Renders a Mermaid call graph for the latest structured Jidoka trace.
  """
  @spec call_graph(Jidoka.Trace.t() | pid() | String.t() | Jido.Agent.t(), keyword()) ::
          {:ok, String.t()} | {:error, String.t()}
  def call_graph(target, opts \\ []) do
    case resolve_trace_target(target, opts) do
      {:ok, trace} ->
        markdown = build_trace_call_graph(trace, opts)
        render_markdown(markdown)
        {:ok, markdown}

      {:error, reason} ->
        message = Jidoka.format_error(reason)
        render_markdown("### Trace Call Graph\n\n#{escape_markdown(message)}")
        {:error, message}
    end
  end

  @doc """
  Renders the raw structured events for the latest Jidoka trace.
  """
  @spec trace_table(Jidoka.Trace.t() | pid() | String.t() | Jido.Agent.t(), keyword()) ::
          {:ok, Jidoka.Trace.t()} | {:error, String.t()}
  def trace_table(target, opts \\ []) do
    case resolve_trace_target(target, opts) do
      {:ok, trace} ->
        rows = Enum.map(trace.events, &trace_event_row/1)
        table("Trace events", rows, keys: [:seq, :category, :event, :phase, :name, :status, :metadata])
        {:ok, trace}

      {:error, reason} ->
        message = Jidoka.format_error(reason)
        render_markdown("### Trace Events\n\n#{escape_markdown(message)}")
        {:error, message}
    end
  end

  @doc """
  Renders a small Markdown table in Livebook.

  This avoids custom widget JavaScript, so it remains stable across Livebook and
  Kino versions.
  """
  @spec table(String.t(), [map()], keyword()) :: :ok
  def table(label, rows, opts \\ []) when is_binary(label) and is_list(rows) do
    keys = Keyword.get(opts, :keys, infer_keys(rows))

    rows
    |> markdown_table(label, keys)
    |> render_markdown()
  end

  defp find_env(names) do
    Enum.find_value(names, fn name ->
      case System.get_env(name) do
        nil -> nil
        "" -> nil
        key -> {name, key}
      end
    end)
  end

  defp clear_empty_env(name) do
    if System.get_env(name) == "" do
      System.delete_env(name)
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

    render_value("Runtime trace: #{label} (#{length(rows)} events)")

    if rows == [] do
      render_value("No runtime events were captured for this call.")
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

    table(label, rows, keys: [:time, :level, :event, :source, :summary])
  end

  defp render_value(value) do
    if Code.ensure_loaded?(Kino) and function_exported?(Kino, :render, 1) do
      apply(Kino, :render, [value])
    else
      :ok
    end
  end

  defp render_chat_result(label, result) do
    table("Turn result: #{label}", [chat_result_row(result)], keys: [:status, :summary])
  end

  defp chat_result_row({:ok, text}), do: %{status: "ok", summary: inspect_value(text, 50)}

  defp chat_result_row({:handoff, summary}) when is_map(summary) do
    %{
      status: "handoff",
      summary:
        [
          "to=#{Map.get(summary, :to_agent_id)}",
          "conversation=#{Map.get(summary, :conversation_id)}",
          Map.get(summary, :reason)
        ]
        |> Enum.reject(&blank?/1)
        |> Enum.join(", ")
    }
  end

  defp chat_result_row({:interrupt, summary}) when is_map(summary) do
    %{status: "interrupt", summary: "#{Map.get(summary, :kind)}: #{Map.get(summary, :message)}"}
  end

  defp chat_result_row({:error, message}), do: %{status: "error", summary: to_string(message)}
  defp chat_result_row(other), do: %{status: "result", summary: inspect_value(other, 50)}

  defp render_markdown(markdown) do
    value =
      if Code.ensure_loaded?(Kino.Markdown) and function_exported?(Kino.Markdown, :new, 1) do
        apply(Kino.Markdown, :new, [markdown])
      else
        markdown
      end

    render_value(value)
  end

  defp inspect_agent_target(%{kind: _kind} = inspection), do: {:ok, inspection}
  defp inspect_agent_target(target), do: Jidoka.inspect_agent(target)

  defp resolve_trace_target(%Jidoka.Trace{} = trace, _opts), do: {:ok, trace}

  defp resolve_trace_target(target, opts) do
    case Keyword.get(opts, :request_id) do
      request_id when is_binary(request_id) -> Jidoka.Trace.for_request(target, request_id, opts)
      _ -> Jidoka.Trace.latest(target, opts)
    end
  end

  defp extract_turn_text(text) when is_binary(text), do: text

  defp extract_turn_text(turn) do
    Jido.AI.Turn.extract_text(turn)
  rescue
    _error -> turn
  end

  defp render_agent_debug(inspection, _opts) do
    table("Agent summary", agent_summary_rows(inspection), keys: [:property, :value])

    definition = inspection_definition(inspection)

    table("Agent capabilities", capability_rows(definition), keys: [:surface, :count, :names])

    table("Agent lifecycle", lifecycle_rows(definition), keys: [:surface, :summary])

    case Map.get(inspection, :last_request) do
      nil -> :ok
      request -> table("Latest request", request_rows(request), keys: [:property, :value])
    end
  end

  defp agent_summary_rows(%{kind: :running_agent} = inspection) do
    definition = inspection_definition(inspection)

    [
      %{property: "kind", value: "running agent"},
      %{property: "id", value: Map.get(inspection, :id)},
      %{property: "name", value: Map.get(inspection, :name)},
      %{property: "runtime", value: format_module(Map.get(inspection, :runtime_module))},
      %{property: "owner", value: format_module(Map.get(inspection, :owner_module))},
      %{property: "model", value: inspect_value(Map.get(definition, :model) || Map.get(definition, :configured_model))},
      %{property: "requests", value: Map.get(inspection, :request_count, 0)},
      %{property: "last request", value: Map.get(inspection, :last_request_id)}
    ]
    |> reject_blank_rows()
  end

  defp agent_summary_rows(definition) when is_map(definition) do
    [
      %{property: "kind", value: Map.get(definition, :kind)},
      %{property: "id", value: Map.get(definition, :id)},
      %{property: "name", value: Map.get(definition, :name)},
      %{property: "module", value: format_module(Map.get(definition, :module))},
      %{property: "runtime", value: format_module(Map.get(definition, :runtime_module))},
      %{property: "model", value: inspect_value(Map.get(definition, :model) || Map.get(definition, :configured_model))},
      %{property: "description", value: Map.get(definition, :description)}
    ]
    |> reject_blank_rows()
  end

  defp capability_rows(definition) when is_map(definition) do
    [
      capability_row("tools", list_value(definition, [:tool_names])),
      capability_row("plugins", list_value(definition, [:plugin_names, :plugins])),
      capability_row("skills", list_value(definition, [:skill_names, :skills])),
      capability_row("workflows", list_value(definition, [:workflow_names, :workflows])),
      capability_row("subagents", list_value(definition, [:subagent_names, :subagents])),
      capability_row("handoffs", list_value(definition, [:handoff_names, :handoffs])),
      capability_row("web", list_value(definition, [:web_tool_names, :web])),
      scalar_capability_row("ash", Map.get(definition, :ash_domain) || Map.get(definition, :ash)),
      capability_row("mcp", list_value(definition, [:mcp_tool_names, :mcp_tools, :mcp]))
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp capability_row(surface, names) when is_list(names) do
    %{surface: surface, count: length(names), names: format_list(names)}
  end

  defp scalar_capability_row(_surface, nil), do: nil

  defp scalar_capability_row(surface, value) do
    %{surface: surface, count: 1, names: inspect_value(value)}
  end

  defp lifecycle_rows(definition) when is_map(definition) do
    [
      %{surface: "memory", summary: inspect_value(Map.get(definition, :memory))},
      %{surface: "output", summary: inspect_value(Map.get(definition, :output))},
      %{surface: "hooks", summary: inspect_value(Map.get(definition, :hooks, %{}))},
      %{surface: "guardrails", summary: inspect_value(Map.get(definition, :guardrails, %{}))}
    ]
  end

  defp request_rows(request) when is_map(request) do
    [
      %{property: "request id", value: Map.get(request, :request_id)},
      %{property: "status", value: Map.get(request, :status)},
      %{property: "model", value: inspect_value(Map.get(request, :model))},
      %{property: "input", value: Map.get(request, :input_message)},
      %{property: "tools", value: format_list(Map.get(request, :tool_names, []))},
      %{property: "mcp tools", value: format_list(Map.get(request, :mcp_tools, []))},
      %{property: "context", value: format_list(Map.get(request, :context_preview, []))},
      %{property: "memory", value: inspect_value(Map.get(request, :memory))},
      %{property: "subagents", value: length(Map.get(request, :subagents, []))},
      %{property: "workflows", value: length(Map.get(request, :workflows, []))},
      %{property: "handoffs", value: length(Map.get(request, :handoffs, []))},
      %{property: "interrupt", value: inspect_value(Map.get(request, :interrupt))},
      %{property: "error", value: inspect_value(Map.get(request, :error))},
      %{property: "usage", value: inspect_value(Map.get(request, :usage))},
      %{property: "duration ms", value: Map.get(request, :duration_ms)},
      %{property: "messages", value: Map.get(request, :message_count)}
    ]
    |> reject_blank_rows()
  end

  defp timeline_row(%Jidoka.Trace.Event{} = event) do
    %{
      seq: event.seq,
      time: format_trace_time(event.at_ms),
      source: event.source,
      event: "#{event.category}.#{event.event}",
      name: event.name || "-",
      status: event.status || "-",
      duration_ms: event.duration_ms || "-"
    }
  end

  defp trace_event_row(%Jidoka.Trace.Event{} = event) do
    %{
      seq: event.seq,
      category: event.category,
      event: event.event,
      phase: event.phase || "-",
      name: event.name || "-",
      status: event.status || "-",
      metadata: inspect_value(compact_trace_metadata(event.metadata), 12)
    }
  end

  defp compact_trace_metadata(metadata) when is_map(metadata) do
    Map.take(metadata, [
      :agent_id,
      :request_id,
      :run_id,
      :tool_name,
      :model,
      :workflow,
      :subagent,
      :handoff,
      :guardrail,
      :hook,
      :namespace,
      :output,
      :schema_kind,
      :conversation_id,
      :child_request_id,
      :error
    ])
  end

  defp format_trace_time(nil), do: ""

  defp format_trace_time(ms) when is_integer(ms) do
    ms
    |> DateTime.from_unix!(:millisecond)
    |> DateTime.to_time()
    |> Time.to_iso8601()
    |> String.slice(0, 12)
  rescue
    _error -> ""
  end

  defp build_trace_call_graph(%Jidoka.Trace{} = trace, opts) do
    direction = Keyword.get(opts, :direction, "TD")
    agent_label = trace.agent_id || trace.request_id || "agent"

    nodes = [
      "flowchart #{direction}",
      "  Agent[\"#{mermaid_label(["Agent", agent_label])}\"]"
    ]

    capability_lines =
      trace.events
      |> Enum.filter(&trace_graph_event?/1)
      |> Enum.uniq_by(fn event ->
        {event.category, event.name, event.metadata[:child_request_id], event.metadata[:conversation_id]}
      end)
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {event, index} ->
        node_id = "N#{index}"
        label = trace_graph_label(event)

        [
          "  #{node_id}[\"#{mermaid_label(label)}\"]",
          "  Agent --> #{node_id}"
        ]
      end)

    ["```mermaid", Enum.join(nodes ++ capability_lines, "\n"), "```"]
    |> Enum.join("\n")
  end

  defp trace_graph_event?(%Jidoka.Trace.Event{category: category, event: event})
       when category in [:model, :tool, :workflow, :subagent, :handoff, :guardrail, :memory, :mcp, :output] do
    event in [:start, :stop, :complete, :completed, :validated, :repair, :error, :interrupt, :retrieve, :capture, :sync]
  end

  defp trace_graph_event?(_event), do: false

  defp trace_graph_label(%Jidoka.Trace.Event{} = event) do
    [
      event.category |> Atom.to_string() |> String.capitalize(),
      event.name,
      event.status
    ]
  end

  defp inspection_definition(value) when is_map(value) do
    cond do
      Map.get(value, :kind) == :running_agent and is_map(Map.get(value, :definition)) ->
        Map.get(value, :definition)

      is_map(Map.get(value, :definition)) ->
        Map.get(value, :definition)

      true ->
        value
    end
  end

  defp build_agent_diagram(inspection, opts) do
    definition = inspection_definition(inspection)
    agent_label = Map.get(inspection, :name) || Map.get(definition, :name) || Map.get(definition, :id) || "agent"
    model = Map.get(definition, :model) || Map.get(definition, :configured_model) || "model"
    context_keys = definition |> Map.get(:context, %{}) |> Map.keys() |> Enum.map(&to_string/1) |> Enum.sort()
    lifecycle = lifecycle_labels(definition)

    capability_nodes =
      [
        {:Tools, "tools", list_value(definition, [:tool_names])},
        {:Workflows, "workflows", list_value(definition, [:workflow_names, :workflows])},
        {:Subagents, "subagents", list_value(definition, [:subagent_names, :subagents])},
        {:Handoffs, "handoffs", list_value(definition, [:handoff_names, :handoffs])},
        {:Web, "web", list_value(definition, [:web_tool_names, :web])},
        {:MCP, "mcp", list_value(definition, [:mcp_tool_names, :mcp_tools, :mcp])}
      ]
      |> Enum.reject(fn {_id, _label, names} -> names == [] end)

    direction = Keyword.get(opts, :direction, "LR")

    nodes = [
      "flowchart #{direction}",
      "  Agent[\"#{mermaid_label(["Agent", agent_label])}\"]",
      "  Model[\"#{mermaid_label(["Model", inspect_value(model, 10)])}\"]",
      "  Context[\"#{mermaid_label(["Context", format_list(context_keys)])}\"]",
      "  Lifecycle[\"#{mermaid_label(["Lifecycle", format_list(lifecycle)])}\"]",
      "  Model --> Agent",
      "  Context --> Agent",
      "  Lifecycle -.-> Agent"
    ]

    capability_lines =
      Enum.flat_map(capability_nodes, fn {node_id, label, names} ->
        [
          "  #{node_id}[\"#{mermaid_label([String.capitalize(label), format_list(names)])}\"]",
          "  Agent --> #{node_id}"
        ]
      end)

    ["```mermaid", Enum.join(nodes ++ capability_lines, "\n"), "```"]
    |> Enum.join("\n")
  end

  defp lifecycle_labels(definition) do
    [
      if_present(Map.get(definition, :memory), "memory"),
      if_present(Map.get(definition, :output), "output"),
      if_present(Map.get(definition, :hooks), "hooks"),
      if_present(Map.get(definition, :guardrails), "guardrails")
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp if_present(nil, _label), do: nil
  defp if_present(%{} = value, _label) when map_size(value) == 0, do: nil
  defp if_present([], _label), do: nil
  defp if_present(_value, label), do: label

  defp list_value(definition, keys) do
    Enum.find_value(keys, [], fn key ->
      definition
      |> Map.get(key)
      |> normalize_names()
      |> case do
        [] -> nil
        names -> names
      end
    end)
  end

  defp normalize_names(nil), do: []
  defp normalize_names(names) when is_list(names), do: names |> Enum.map(&normalize_name/1) |> Enum.reject(&blank?/1)
  defp normalize_names(%{} = map), do: map |> Map.keys() |> Enum.map(&normalize_name/1) |> Enum.reject(&blank?/1)
  defp normalize_names(value), do: [normalize_name(value)] |> Enum.reject(&blank?/1)

  defp normalize_name(value) when is_binary(value), do: value
  defp normalize_name(value) when is_atom(value), do: value |> Atom.to_string() |> String.replace_prefix("Elixir.", "")
  defp normalize_name(%{name: name}), do: normalize_name(name)
  defp normalize_name(%{"name" => name}), do: normalize_name(name)
  defp normalize_name(value), do: inspect_value(value, 8)

  defp handoff_summary(%Jidoka.Handoff{} = handoff) do
    %{
      id: handoff.id,
      name: handoff.name,
      conversation_id: handoff.conversation_id,
      from_agent: handoff.from_agent,
      to_agent: handoff.to_agent,
      to_agent_id: handoff.to_agent_id,
      message: handoff.message,
      summary: handoff.summary,
      reason: handoff.reason,
      context_keys: handoff.context |> Map.keys() |> Enum.map(&to_string/1) |> Enum.sort(),
      request_id: handoff.request_id
    }
  end

  defp interrupt_summary(%Jidoka.Interrupt{} = interrupt) do
    %{
      id: interrupt.id,
      kind: interrupt.kind,
      message: interrupt.message,
      data_keys: interrupt.data |> Map.keys() |> Enum.map(&to_string/1) |> Enum.sort(),
      data: interrupt.data
    }
  end

  defp context_visibility(key) do
    if internal_context_key?(key), do: "internal", else: "public"
  end

  defp visibility_order("public"), do: 0
  defp visibility_order("internal"), do: 1
  defp visibility_order(_), do: 2

  defp internal_context_key?(key) when is_atom(key), do: key |> Atom.to_string() |> internal_context_key?()

  defp internal_context_key?(key) when is_binary(key) do
    key = String.trim(key)

    String.starts_with?(key, "__jidoka") or String.starts_with?(key, "__tool_guardrail") or
      String.starts_with?(key, "__")
  end

  defp internal_context_key?(_key), do: false

  defp value_type(value) when is_binary(value), do: "string"
  defp value_type(value) when is_integer(value), do: "integer"
  defp value_type(value) when is_float(value), do: "float"
  defp value_type(value) when is_boolean(value), do: "boolean"
  defp value_type(value) when is_atom(value), do: "atom"
  defp value_type(value) when is_list(value), do: "list"
  defp value_type(value) when is_map(value), do: "map"
  defp value_type(value) when is_pid(value), do: "pid"
  defp value_type(_value), do: "term"

  defp format_context_key(key) when is_atom(key), do: Atom.to_string(key)
  defp format_context_key(key) when is_binary(key), do: key
  defp format_context_key(key), do: inspect(key)

  defp inspect_value(value, limit \\ 18), do: inspect(value, pretty: false, limit: limit)

  defp format_module(nil), do: nil
  defp format_module(module) when is_atom(module), do: inspect(module)
  defp format_module(other), do: inspect_value(other)

  defp format_list([]), do: "-"
  defp format_list(values) when is_list(values), do: Enum.join(values, ", ")
  defp format_list(value), do: inspect_value(value)

  defp reject_blank_rows(rows) do
    Enum.reject(rows, fn row -> blank?(Map.get(row, :value)) end)
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?("-"), do: true
  defp blank?([]), do: true
  defp blank?(_value), do: false

  defp mermaid_label(parts) do
    parts
    |> Enum.reject(&blank?/1)
    |> Enum.map(&to_string/1)
    |> Enum.map(&mermaid_label_part/1)
    |> Enum.join("\\n")
  end

  defp mermaid_label_part(part) do
    part
    |> String.replace("\\", "/")
    |> String.replace("\"", "'")
    |> String.replace("[", "(")
    |> String.replace("]", ")")
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
        params = match |> Enum.at(2) |> compact()
        shorten("#{module} #{params}", 180)

      match = Regex.run(~r/AgentServer ([^\s]+) spawned child ([^\s]+)/, message) ->
        "#{Enum.at(match, 1)} -> #{Enum.at(match, 2)}"

      true ->
        message |> compact() |> shorten(180)
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

  defp compact(message) do
    message
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp shorten(message, max_length) do
    if String.length(message) <= max_length do
      message
    else
      String.slice(message, 0, max_length - 1) <> "..."
    end
  end

  defp infer_keys([]), do: []

  defp infer_keys([%{} = row | _rows]) do
    row
    |> Map.keys()
    |> Enum.sort()
  end

  defp markdown_table(_rows, label, []), do: "### #{escape_markdown(label)}\n\n_No rows._"

  defp markdown_table(rows, label, keys) do
    headers =
      keys
      |> Enum.map(&header/1)
      |> Enum.join(" | ")

    separator =
      keys
      |> Enum.map(fn _key -> "---" end)
      |> Enum.join(" | ")

    body =
      rows
      |> Enum.map(fn row ->
        keys
        |> Enum.map(fn key -> row |> Map.get(key, "") |> table_cell() end)
        |> Enum.join(" | ")
      end)
      |> Enum.join("\n")

    "### #{escape_markdown(label)}\n\n| #{headers} |\n| #{separator} |\n#{body_rows(body)}"
  end

  defp body_rows(""), do: ""
  defp body_rows(body), do: "| #{body} |"

  defp header(key) do
    key
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
    |> escape_table_cell()
  end

  defp table_cell(value) when is_binary(value), do: escape_table_cell(value)
  defp table_cell(value), do: value |> inspect() |> escape_table_cell()

  defp escape_markdown(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("#", "\\#")
  end

  defp escape_table_cell(value) do
    value
    |> compact()
    |> shorten(220)
    |> String.replace("\\", "\\\\")
    |> String.replace("|", "\\|")
  end
end
