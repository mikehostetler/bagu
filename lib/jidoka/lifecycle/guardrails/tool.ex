defmodule Jidoka.Guardrails.Tool do
  @moduledoc false

  @enforce_keys [
    :agent,
    :server,
    :request_id,
    :tool_name,
    :arguments,
    :context,
    :metadata,
    :request_opts
  ]
  defstruct [
    :agent,
    :server,
    :request_id,
    :tool_name,
    :tool_call_id,
    :arguments,
    :context,
    :metadata,
    :request_opts
  ]

  @type t :: %__MODULE__{
          agent: Jido.Agent.t(),
          server: pid(),
          request_id: String.t() | nil,
          tool_name: String.t() | atom(),
          tool_call_id: String.t() | nil,
          arguments: term(),
          context: map(),
          metadata: map(),
          request_opts: map()
        }
end
