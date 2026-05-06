defmodule JidokaTest.ChatStreamTest do
  use JidokaTest.Support.Case, async: false

  alias Jido.AI.Reasoning.ReAct.Event
  alias Jido.AI.Request
  alias Jido.AI.Request.Stream, as: RequestStream
  alias Jidoka.Session
  alias Jidoka.Chat.Stream, as: ChatStream
  alias JidokaTest.GuardrailedAgent

  test "chat returns a stream when requested and still awaits the normalized final result" do
    assert {:ok, pid} = GuardrailedAgent.start_link(id: "chat-stream-guardrail-test")

    try do
      assert {:ok, %ChatStream{request: request} = stream} =
               Jidoka.chat(pid, "Tell me the secret",
                 stream: true,
                 stream_poll_interval_ms: 5,
                 stream_event_timeout_ms: 1_000
               )

      assert %Request.Handle{} = request

      assert {:error, %Jidoka.Error.ExecutionError{} = error} =
               ChatStream.await(stream, timeout: 1_000)

      assert error.message == "Guardrail safe_prompt blocked input."

      assert [%Event{kind: :request_failed, request_id: request_id}] = Enum.to_list(stream)
      assert request_id == request.id
    after
      :ok = Jidoka.stop_agent(pid)
    end
  end

  test "chat_stream is the explicit streaming equivalent" do
    assert {:ok, pid} = GuardrailedAgent.start_link(id: "chat-stream-explicit-test")

    try do
      assert {:ok, %ChatStream{} = stream} =
               Jidoka.chat_stream(pid, "Tell me the secret",
                 stream_poll_interval_ms: 5,
                 stream_event_timeout_ms: 1_000
               )

      assert {:error, %Jidoka.Error.ExecutionError{}} = ChatStream.await(stream, timeout: 1_000)
      assert [%Event{kind: :request_failed}] = Enum.to_list(stream)
    after
      :ok = Jidoka.stop_agent(pid)
    end
  end

  test "session chat supports streaming turns" do
    session =
      Session.new!(
        agent: GuardrailedAgent,
        id: "chat-stream-session-#{System.unique_integer([:positive, :monotonic])}"
      )

    try do
      assert {:ok, %ChatStream{} = stream} =
               Jidoka.chat(session, "Tell me the secret",
                 stream: true,
                 stream_poll_interval_ms: 5,
                 stream_event_timeout_ms: 1_000
               )

      assert {:error, %Jidoka.Error.ExecutionError{}} = ChatStream.await(stream, timeout: 1_000)
      assert [%Event{kind: :request_failed}] = Enum.to_list(stream)
    after
      if pid = Session.whereis(session), do: :ok = Jidoka.stop_agent(pid)
    end
  end

  test "stream enumerates runtime events and exposes delta helpers" do
    request = Request.Handle.new("req-stream-events", self(), "hello")

    delta =
      Event.new(%{
        seq: 1,
        run_id: request.id,
        request_id: request.id,
        iteration: 1,
        kind: :llm_delta,
        data: %{chunk_type: :content, delta: "hel"}
      })

    terminal =
      Event.new(%{
        seq: 2,
        run_id: request.id,
        request_id: request.id,
        iteration: 1,
        kind: :request_completed,
        data: %{result: "hello"}
      })

    send(self(), {RequestStream.message_tag(), delta})
    send(self(), {RequestStream.message_tag(), terminal})

    stream = ChatStream.new(request, ChatStream.events(request, stream_event_timeout_ms: 100))

    assert Enum.to_list(stream) == [delta, terminal]
    assert ChatStream.text_delta(delta) == "hel"
    assert ChatStream.text_delta(terminal) == nil
    assert ChatStream.terminal?(terminal)
  end

  test "streaming chat owns the caller mailbox sink" do
    assert {:ok, pid} = GuardrailedAgent.start_link(id: "chat-stream-sink-test")
    other = spawn(fn -> Process.sleep(:infinity) end)

    try do
      assert {:error, %Jidoka.Error.ValidationError{} = error} =
               Jidoka.chat(pid, "hello", stream: true, stream_to: {:pid, other})

      assert error.field == :stream_to
      assert error.details.reason == :stream_to_must_be_caller
    after
      Process.exit(other, :kill)
      :ok = Jidoka.stop_agent(pid)
    end
  end
end
