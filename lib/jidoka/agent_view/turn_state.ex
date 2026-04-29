defmodule Jidoka.AgentView.TurnState do
  @moduledoc false

  alias Jido.AI.Request
  alias Jidoka.AgentView.Run

  @spec build_run(module(), Request.Handle.t(), term(), keyword()) :: Run.t()
  def build_run(view_module, %Request.Handle{} = request, input, opts) do
    %Run{
      request: request,
      agent_ref: request.server,
      request_id: request.id,
      conversation_id: Keyword.get(opts, :conversation, view_module.conversation_id(input)),
      view_module: view_module,
      input: input,
      metadata: %{timeout: Keyword.get(opts, :timeout, 30_000)}
    }
  end

  @spec before_turn(map(), String.t()) :: map()
  def before_turn(view, message) when is_binary(message) do
    content = String.trim(message)

    if content == "" do
      %{view | status: :idle}
    else
      pending = %{
        id: "pending-" <> Integer.to_string(System.unique_integer([:positive, :monotonic])),
        seq: -1,
        role: :user,
        content: content,
        pending?: true
      }

      %{
        view
        | visible_messages: view.visible_messages ++ [pending],
          streaming_message: nil,
          status: :running,
          error: nil,
          error_text: nil,
          outcome: nil
      }
    end
  end

  @spec apply_result(map(), term()) :: map()
  def apply_result(view, {:error, reason}) do
    %{
      view
      | streaming_message: nil,
        status: :error,
        error: reason,
        error_text: Jidoka.Error.format(reason),
        outcome: {:error, reason}
    }
  end

  def apply_result(view, {:interrupt, interrupt}) do
    %{
      view
      | streaming_message: nil,
        status: :interrupted,
        error: nil,
        error_text: interrupt.message,
        outcome: {:interrupt, interrupt}
    }
  end

  def apply_result(view, {:handoff, handoff}) do
    %{
      view
      | streaming_message: nil,
        status: :handoff,
        error: nil,
        error_text: "Conversation handed off to #{handoff.to_agent_id}.",
        outcome: {:handoff, handoff}
    }
  end

  def apply_result(view, {:ok, reply}) do
    %{view | streaming_message: nil, status: :idle, error: nil, error_text: nil, outcome: {:ok, reply}}
  end

  @spec running_visible_messages([map()], [map()]) :: [map()]
  def running_visible_messages(current_messages, refreshed_messages) do
    if refreshed_messages == [] do
      current_messages
    else
      refreshed_messages
    end
  end
end
