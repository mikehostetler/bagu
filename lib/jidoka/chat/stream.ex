defmodule Jidoka.Chat.Stream do
  @moduledoc """
  Request-scoped streaming chat result.

  `Jidoka.chat(target, message, stream: true)` returns `{:ok, stream}` where
  `stream` is enumerable over Jido.AI runtime events for that request. Use
  `await/2` when you also need Jidoka's normalized final chat result.
  """

  alias Jido.AI.Reasoning.ReAct.Event
  alias Jido.AI.Request
  alias Jido.AI.Request.Stream, as: RequestStream

  @message_tag :jido_ai_request_event
  @default_poll_interval_ms 100

  @type t :: %__MODULE__{
          request: Request.Handle.t(),
          events: Enumerable.t()
        }

  defstruct [:request, :events]

  @doc false
  @spec new(Request.Handle.t(), Enumerable.t()) :: t()
  def new(%Request.Handle{} = request, events) do
    %__MODULE__{request: request, events: events}
  end

  @doc """
  Builds an enumerable over request runtime events.

  The enumerable consumes Jido.AI stream events from the caller mailbox and also
  polls request state so Jidoka lifecycle short-circuits, such as guardrail
  blocks before a model call, still terminate the stream.
  """
  @spec events(Request.Handle.t(), keyword()) :: Enumerable.t()
  def events(%Request.Handle{} = request, opts \\ []) when is_list(opts) do
    Stream.resource(
      fn -> initial_state(request, opts) end,
      &next_event/1,
      fn _state -> :ok end
    )
  end

  @doc """
  Waits for the final normalized result for a streaming chat turn.
  """
  @spec await(t(), keyword()) ::
          {:ok, term()} | {:error, term()} | {:interrupt, Jidoka.Interrupt.t()} | {:handoff, Jidoka.Handoff.t()}
  def await(%__MODULE__{request: %Request.Handle{} = request}, opts \\ []) when is_list(opts) do
    Jidoka.Chat.await_chat_request(request, opts)
  end

  @doc """
  Returns true when a runtime event terminates the request stream.
  """
  @spec terminal?(Event.t()) :: boolean()
  def terminal?(%Event{kind: kind}), do: RequestStream.terminal_kind?(kind)

  @doc """
  Extracts a content delta from an `:llm_delta` event, when present.
  """
  @spec text_delta(Event.t()) :: String.t() | nil
  def text_delta(%Event{kind: :llm_delta, data: data}) when is_map(data) do
    if content_delta?(data), do: string_value(data, :delta), else: nil
  end

  def text_delta(_event), do: nil

  @doc """
  Extracts a thinking/reasoning delta from an `:llm_delta` event, when present.
  """
  @spec thinking_delta(Event.t()) :: String.t() | nil
  def thinking_delta(%Event{kind: :llm_delta, data: data}) when is_map(data) do
    if thinking_delta?(data), do: string_value(data, :delta), else: nil
  end

  def thinking_delta(_event), do: nil

  defp initial_state(%Request.Handle{} = request, opts) do
    timeout = Keyword.get(opts, :stream_event_timeout_ms, :infinity)

    %{
      request: request,
      done?: false,
      poll_interval_ms: poll_interval_ms(opts),
      timeout_ms: timeout_ms(timeout),
      deadline_ms: deadline_ms(timeout)
    }
  end

  defp next_event(%{done?: true} = state), do: {:halt, state}

  defp next_event(%{request: %Request.Handle{id: request_id}} = state) do
    receive_timeout = receive_timeout_ms(state)

    receive do
      {@message_tag, %Event{request_id: ^request_id} = event} ->
        {[event], event_state(state, event)}
    after
      receive_timeout ->
        state
        |> maybe_terminal_event()
        |> case do
          {:ok, event, state} -> {[event], event_state(state, event)}
          {:timeout, state} -> {:halt, %{state | done?: true}}
          {:pending, state} -> {[], state}
        end
    end
  end

  defp maybe_terminal_event(%{request: %Request.Handle{id: request_id, server: server}} = state) do
    cond do
      expired?(state) ->
        {:timeout, state}

      true ->
        case request_status(server, request_id) do
          {:completed, result} -> {:ok, completed_event(request_id, result), state}
          {:failed, error} -> {:ok, RequestStream.failed_event(request_id, error, reason: :request_failed), state}
          :pending -> {:pending, state}
        end
    end
  end

  defp request_status(server, request_id) do
    case Jido.AgentServer.state(server) do
      {:ok, %{agent: agent}} ->
        case Request.get_request(agent, request_id) do
          %{status: :completed, result: result} -> {:completed, result}
          %{status: :failed, error: error} -> {:failed, error}
          _request -> :pending
        end

      {:error, reason} ->
        {:failed, {:agent_unavailable, reason}}
    end
  rescue
    error -> {:failed, error}
  end

  defp completed_event(request_id, result) do
    Event.new(%{
      seq: 0,
      run_id: request_id,
      request_id: request_id,
      iteration: 0,
      kind: :request_completed,
      data: %{result: result}
    })
  end

  defp event_state(state, %Event{} = event) do
    %{state | done?: terminal?(event), deadline_ms: deadline_ms(state.timeout_ms)}
  end

  defp poll_interval_ms(opts) do
    opts
    |> Keyword.get(:stream_poll_interval_ms, @default_poll_interval_ms)
    |> case do
      interval when is_integer(interval) and interval > 0 -> interval
      _other -> @default_poll_interval_ms
    end
  end

  defp timeout_ms(:infinity), do: :infinity
  defp timeout_ms(timeout) when is_integer(timeout) and timeout >= 0, do: timeout
  defp timeout_ms(_timeout), do: :infinity

  defp deadline_ms(:infinity), do: :infinity
  defp deadline_ms(timeout) when is_integer(timeout), do: monotonic_ms() + timeout

  defp receive_timeout_ms(%{deadline_ms: :infinity, poll_interval_ms: interval}), do: interval

  defp receive_timeout_ms(%{deadline_ms: deadline, poll_interval_ms: interval}) do
    max(0, min(interval, deadline - monotonic_ms()))
  end

  defp expired?(%{deadline_ms: :infinity}), do: false
  defp expired?(%{deadline_ms: deadline}), do: monotonic_ms() >= deadline

  defp monotonic_ms, do: System.monotonic_time(:millisecond)

  defp content_delta?(data),
    do: delta_kind(data) in [:content, "content", nil] and is_binary(string_value(data, :delta))

  defp thinking_delta?(data), do: delta_kind(data) in [:thinking, :reasoning, "thinking", "reasoning"]

  defp delta_kind(data), do: Map.get(data, :chunk_type, Map.get(data, "chunk_type"))

  defp string_value(data, key) do
    case Map.get(data, key, Map.get(data, Atom.to_string(key))) do
      value when is_binary(value) -> value
      _other -> nil
    end
  end
end

defimpl Enumerable, for: Jidoka.Chat.Stream do
  def reduce(%Jidoka.Chat.Stream{events: events}, acc, fun), do: Enumerable.reduce(events, acc, fun)
  def count(_stream), do: {:error, __MODULE__}
  def member?(_stream, _event), do: {:error, __MODULE__}
  def slice(_stream), do: {:error, __MODULE__}
end
