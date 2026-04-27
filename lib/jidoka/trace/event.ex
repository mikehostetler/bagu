defmodule Jidoka.Trace.Event do
  @moduledoc """
  Normalized Jidoka trace event.

  Events are a Jidoka-friendly projection of Jido/Jido.AI telemetry plus
  Jidoka-specific lifecycle events.
  """

  @type t :: %__MODULE__{
          seq: pos_integer(),
          at_ms: integer(),
          source: atom(),
          category: atom(),
          event: atom(),
          phase: atom() | nil,
          name: String.t() | nil,
          status: atom() | nil,
          duration_ms: non_neg_integer() | nil,
          request_id: String.t() | nil,
          run_id: String.t() | nil,
          trace_id: String.t() | nil,
          span_id: String.t() | nil,
          parent_span_id: String.t() | nil,
          measurements: map(),
          metadata: map()
        }

  @enforce_keys [
    :seq,
    :at_ms,
    :source,
    :category,
    :event,
    :measurements,
    :metadata
  ]
  defstruct [
    :seq,
    :at_ms,
    :source,
    :category,
    :event,
    :phase,
    :name,
    :status,
    :duration_ms,
    :request_id,
    :run_id,
    :trace_id,
    :span_id,
    :parent_span_id,
    measurements: %{},
    metadata: %{}
  ]
end
