defmodule Jidoka.Kino.TraceView do
  @moduledoc false

  alias Jidoka.Kino.Render

  @spec timeline(Jidoka.Trace.t() | pid() | String.t() | Jido.Agent.t(), keyword()) ::
          {:ok, Jidoka.Trace.t()} | {:error, String.t()}
  def timeline(target, opts \\ []) do
    case resolve_trace_target(target, opts) do
      {:ok, trace} ->
        rows = Enum.map(trace.events, &timeline_row/1)
        Render.table("Trace timeline", rows, keys: [:seq, :time, :source, :event, :name, :status, :duration_ms])
        {:ok, trace}

      {:error, reason} ->
        message = Jidoka.Error.format(reason)
        Render.markdown("### Trace Timeline\n\n#{Render.escape_markdown(message)}")
        {:error, message}
    end
  end

  @spec call_graph(Jidoka.Trace.t() | pid() | String.t() | Jido.Agent.t(), keyword()) ::
          {:ok, String.t()} | {:error, String.t()}
  def call_graph(target, opts \\ []) do
    case resolve_trace_target(target, opts) do
      {:ok, trace} ->
        markdown = build_trace_call_graph(trace, opts)
        Render.markdown(markdown)
        {:ok, markdown}

      {:error, reason} ->
        message = Jidoka.Error.format(reason)
        Render.markdown("### Trace Call Graph\n\n#{Render.escape_markdown(message)}")
        {:error, message}
    end
  end

  @spec trace_table(Jidoka.Trace.t() | pid() | String.t() | Jido.Agent.t(), keyword()) ::
          {:ok, Jidoka.Trace.t()} | {:error, String.t()}
  def trace_table(target, opts \\ []) do
    case resolve_trace_target(target, opts) do
      {:ok, trace} ->
        rows = Enum.map(trace.events, &trace_event_row/1)
        Render.table("Trace events", rows, keys: [:seq, :category, :event, :phase, :name, :status, :metadata])
        {:ok, trace}

      {:error, reason} ->
        message = Jidoka.Error.format(reason)
        Render.markdown("### Trace Events\n\n#{Render.escape_markdown(message)}")
        {:error, message}
    end
  end

  defp resolve_trace_target(%Jidoka.Trace{} = trace, _opts), do: {:ok, trace}

  defp resolve_trace_target(target, opts) do
    case Keyword.get(opts, :request_id) do
      request_id when is_binary(request_id) -> Jidoka.Trace.for_request(target, request_id, opts)
      _ -> Jidoka.Trace.latest(target, opts)
    end
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
      metadata: Render.inspect_value(compact_trace_metadata(event.metadata), 12)
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
      "  Agent[\"#{Render.mermaid_label(["Agent", agent_label])}\"]"
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
          "  #{node_id}[\"#{Render.mermaid_label(label)}\"]",
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
end
