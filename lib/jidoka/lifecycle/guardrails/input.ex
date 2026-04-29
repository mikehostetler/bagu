defmodule Jidoka.Guardrails.Input do
  @moduledoc false

  @enforce_keys [
    :agent,
    :server,
    :request_id,
    :message,
    :context,
    :allowed_tools,
    :llm_opts,
    :metadata,
    :request_opts
  ]
  defstruct [
    :agent,
    :server,
    :request_id,
    :message,
    :context,
    :allowed_tools,
    :llm_opts,
    :metadata,
    :request_opts
  ]

  @type t :: %__MODULE__{
          agent: Jido.Agent.t(),
          server: pid(),
          request_id: String.t() | nil,
          message: term(),
          context: map(),
          allowed_tools: term(),
          llm_opts: keyword(),
          metadata: map(),
          request_opts: map()
        }
end
