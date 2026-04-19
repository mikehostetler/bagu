defmodule Jido.Signal.Ext.Trace do
  @moduledoc """
  Trace extension for Jido Signal correlation and debugging.

  Provides fields for tracking signal causation and distributed tracing:

  * `trace_id` - constant for entire call chain (32 hex chars, 128-bit)
  * `span_id` - unique for this signal (16 hex chars, 64-bit)
  * `parent_span_id` - span that triggered this signal
  * `causation_id` - signal ID that caused this signal
  * `tracestate` - optional W3C tracestate for vendor-specific data

  ## W3C Trace Context Compatibility

  This extension supports the W3C Trace Context standard for distributed tracing.
  When serialized, it includes a `traceparent` header in the standard format:

      00-{trace_id}-{span_id}-01

  This enables interoperability with OpenTelemetry and other W3C-compatible systems.

  ## CloudEvents Distributed Tracing Extension

  Serializes to CloudEvents distributed tracing extension attributes:
  - `traceparent` - W3C traceparent header
  - `tracestate` - W3C tracestate (optional)
  - `trace_id`, `span_id` - Individual fields for convenience
  - `parent_span_id`, `causation_id` - Jido-specific fields

  ## See Also

  * `Jido.Signal.Trace` - Helper functions for trace management
  * `Jido.Signal.TraceContext` - Process-dictionary context management
  * W3C Trace Context: https://www.w3.org/TR/trace-context/
  """

  use Jido.Signal.Ext,
    namespace: "correlation",
    schema: [
      trace_id: [type: :string, required: true, doc: "Shared trace identifier (32 hex chars)"],
      span_id: [type: :string, required: true, doc: "Unique span identifier (16 hex chars)"],
      parent_span_id: [type: :string, doc: "Parent span identifier"],
      causation_id: [type: :string, doc: "Causing signal ID"],
      tracestate: [type: :string, doc: "W3C tracestate for vendor-specific data"]
    ]

  @w3c_version "00"
  @sampled_flag "01"

  @impl true
  def to_attrs(%{trace_id: trace_id, span_id: span_id} = data) do
    traceparent = build_traceparent(trace_id, span_id)

    %{
      "traceparent" => traceparent,
      "trace_id" => trace_id,
      "span_id" => span_id
    }
    |> maybe_put("tracestate", data[:tracestate])
    |> maybe_put("parent_span_id", data[:parent_span_id])
    |> maybe_put("causation_id", data[:causation_id])
  end

  @impl true
  def from_attrs(attrs) do
    case parse_traceparent(Map.get(attrs, "traceparent")) do
      {:ok, trace_id, span_id} ->
        build_trace_data(trace_id, span_id, attrs)

      :error ->
        parse_legacy_attrs(attrs)
    end
  end

  defp build_traceparent(trace_id, span_id) do
    Enum.join([@w3c_version, trace_id, span_id, @sampled_flag], "-")
  end

  defp parse_traceparent(nil), do: :error

  defp parse_traceparent(traceparent) when is_binary(traceparent) do
    case String.split(traceparent, "-", trim: true) do
      [@w3c_version, trace_id, span_id, _flags]
      when byte_size(trace_id) == 32 and byte_size(span_id) == 16 ->
        if valid_hex?(trace_id) and valid_hex?(span_id) do
          {:ok, trace_id, span_id}
        else
          :error
        end

      _ ->
        :error
    end
  end

  defp parse_legacy_attrs(attrs) do
    case Map.get(attrs, "trace_id") do
      nil ->
        nil

      trace_id ->
        build_trace_data(trace_id, Map.get(attrs, "span_id"), attrs)
    end
  end

  defp build_trace_data(trace_id, span_id, attrs) do
    %{
      trace_id: trace_id,
      span_id: span_id
    }
    |> maybe_put_field(:parent_span_id, Map.get(attrs, "parent_span_id"))
    |> maybe_put_field(:causation_id, Map.get(attrs, "causation_id"))
    |> maybe_put_field(:tracestate, Map.get(attrs, "tracestate"))
  end

  defp valid_hex?(str) when is_binary(str) do
    String.match?(str, ~r/^[0-9a-f]+$/)
  end

  defp maybe_put_field(map, _key, nil), do: map
  defp maybe_put_field(map, key, value), do: Map.put(map, key, value)

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
