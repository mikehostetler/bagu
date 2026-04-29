defmodule Jidoka.AgentView.Run do
  @moduledoc """
  In-flight AgentView turn handle.

  The request server may differ from the originally supplied agent when
  conversation handoff routing is active, so callers should use this run handle
  for refresh and completion projection.
  """

  alias Jido.AI.Request

  @type t :: %__MODULE__{
          request: Request.Handle.t(),
          agent_ref: Request.server(),
          request_id: String.t(),
          conversation_id: String.t(),
          view_module: module(),
          input: term(),
          metadata: map()
        }

  @enforce_keys [:request, :agent_ref, :request_id, :conversation_id, :view_module, :input]
  defstruct [:request, :agent_ref, :request_id, :conversation_id, :view_module, :input, metadata: %{}]
end
