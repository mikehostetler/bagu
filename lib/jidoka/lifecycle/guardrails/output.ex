defmodule Jidoka.Guardrails.Output do
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
    :request_opts,
    :outcome
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
    :request_opts,
    :outcome
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
          request_opts: map(),
          outcome: term()
        }
end
