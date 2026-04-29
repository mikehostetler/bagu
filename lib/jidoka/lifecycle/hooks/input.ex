defmodule Jidoka.Hooks.BeforeTurn do
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

  @type t :: %__MODULE__{}
end

defmodule Jidoka.Hooks.AfterTurn do
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

  @type t :: %__MODULE__{}
end

defmodule Jidoka.Hooks.InterruptInput do
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
    :interrupt
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
    :interrupt
  ]

  @type t :: %__MODULE__{}
end
