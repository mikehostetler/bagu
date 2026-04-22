defmodule MotoTest.ContextMemoryTest do
  use MotoTest.Support.Case, async: false

  alias MotoTest.{
    ChatAgent,
    ContextAgent,
    ContextMemoryAgent,
    MemoryAgent,
    NoCaptureMemoryAgent,
    SharedMemoryAgent
  }

  test "accepts context keyword lists and normalizes them to internal tool_context" do
    assert {:ok, opts} =
             Moto.Agent.prepare_chat_opts([context: [tenant: "acme", locale: "en-US"]], nil)

    assert Keyword.get(opts, :tool_context) == %{tenant: "acme", locale: "en-US"}
  end

  test "rejects malformed context lists with a tagged error instead of raising" do
    assert {:error, {:invalid_context, :expected_map}} =
             Moto.Agent.prepare_chat_opts([context: [1, 2]], nil)
  end

  test "merges default agent context with per-turn context" do
    assert {:ok, opts} =
             Moto.Agent.prepare_chat_opts(
               [context: %{session: "runtime"}],
               %{context: ContextAgent.context(), context_schema: ContextAgent.context_schema()}
             )

    assert Keyword.get(opts, :tool_context) == %{
             tenant: "demo",
             channel: "test",
             session: "runtime"
           }
  end

  test "validates runtime context through the agent schema" do
    assert {:error, {:invalid_context, {:schema, errors}}} =
             Moto.Agent.prepare_chat_opts(
               [context: %{tenant: 123}],
               %{context: ContextAgent.context(), context_schema: ContextAgent.context_schema()}
             )

    assert inspect(errors) =~ "tenant"
  end

  test "Moto.chat validates context through the running agent schema" do
    assert {:ok, pid} = ContextAgent.start_link(id: "context-schema-chat")

    assert {:error, {:invalid_context, {:schema, errors}}} =
             Moto.chat(pid, "hello", context: %{tenant: 123})

    assert inspect(errors) =~ "tenant"
    assert :ok = Moto.stop_agent(pid)
  end

  test "merges default agent context into runtime requests" do
    runtime = ContextAgent.runtime_module()
    agent = new_runtime_agent(runtime)

    assert {:ok, _agent, {:ai_react_start, params}} =
             runtime.on_before_cmd(
               agent,
               {:ai_react_start, %{query: "hello", request_id: "req-context-1"}}
             )

    assert Moto.Context.strip_internal(params.tool_context) == %{tenant: "demo", channel: "test"}

    assert Moto.Context.strip_internal(params.runtime_context) == %{
             tenant: "demo",
             channel: "test"
           }
  end

  test "retrieves and captures conversation memory across turns" do
    runtime = MemoryAgent.runtime_module()
    agent = new_runtime_agent(runtime)
    session = "memory-session-#{System.unique_integer([:positive])}"

    {:ok, agent, _action} =
      runtime.on_before_cmd(
        agent,
        {:ai_react_start,
         %{
           query: "Remember that my favorite color is blue.",
           request_id: "req-memory-1",
           tool_context: %{session: session}
         }}
      )

    agent =
      Jido.AI.Request.complete_request(
        agent,
        "req-memory-1",
        "I'll remember that your favorite color is blue."
      )

    assert {:ok, agent, []} =
             runtime.on_after_cmd(agent, {:ai_react_start, %{request_id: "req-memory-1"}}, [])

    assert {:ok, agent, {:ai_react_start, params}} =
             runtime.on_before_cmd(
               agent,
               {:ai_react_start,
                %{
                  query: "What is my favorite color?",
                  request_id: "req-memory-2",
                  tool_context: %{session: session}
                }}
             )

    memory = params.tool_context[Moto.Memory.context_key()]
    assert memory.namespace == "agent:memory_agent:context:session:#{session}"
    assert Enum.map(memory.records, & &1.kind) == [:user_turn, :assistant_turn]
    assert params.runtime_context.session == session

    assert params.runtime_context[Moto.Memory.context_key()].namespace ==
             "agent:memory_agent:context:session:#{session}"

    assert memory.prompt =~ "Relevant memory:"
    assert memory.prompt =~ "favorite color is blue"

    assert get_in(agent.state, [:requests, "req-memory-2", :meta, :moto_memory, :namespace]) ==
             "agent:memory_agent:context:session:#{session}"
  end

  test "inject :context exposes retrieved memory on the runtime context" do
    runtime = ContextMemoryAgent.runtime_module()
    agent = new_runtime_agent(runtime)
    session = "context-memory-#{System.unique_integer([:positive])}"

    {:ok, agent, _action} =
      runtime.on_before_cmd(
        agent,
        {:ai_react_start,
         %{
           query: "Remember that I prefer green tea.",
           request_id: "req-memory-ctx-1",
           tool_context: %{session: session}
         }}
      )

    agent = Jido.AI.Request.complete_request(agent, "req-memory-ctx-1", "I'll remember that.")

    assert {:ok, agent, []} =
             runtime.on_after_cmd(agent, {:ai_react_start, %{request_id: "req-memory-ctx-1"}}, [])

    assert {:ok, _agent, {:ai_react_start, params}} =
             runtime.on_before_cmd(
               agent,
               {:ai_react_start,
                %{
                  query: "What drink do I prefer?",
                  request_id: "req-memory-ctx-2",
                  tool_context: %{session: session}
                }}
             )

    assert ContextMemoryAgent.request_transformer() == nil
    assert %{namespace: _, records: [_user, _assistant]} = params.tool_context[:memory]
  end

  test "shared memory namespaces are visible across agent instances" do
    runtime = SharedMemoryAgent.runtime_module()
    first_agent = new_runtime_agent(runtime)
    second_agent = new_runtime_agent(runtime)

    {:ok, first_agent, _action} =
      runtime.on_before_cmd(
        first_agent,
        {:ai_react_start, %{query: "Remember that the shared color is red.", request_id: "req-memory-shared-1"}}
      )

    first_agent = Jido.AI.Request.complete_request(first_agent, "req-memory-shared-1", "Stored.")

    assert {:ok, _first_agent, []} =
             runtime.on_after_cmd(
               first_agent,
               {:ai_react_start, %{request_id: "req-memory-shared-1"}},
               []
             )

    assert {:ok, _second_agent, {:ai_react_start, params}} =
             runtime.on_before_cmd(
               second_agent,
               {:ai_react_start, %{query: "What is the shared color?", request_id: "req-memory-shared-2"}}
             )

    assert params.tool_context[:memory].namespace == "shared:shared-demo"

    assert Enum.any?(params.tool_context[:memory].records, fn record ->
             to_string(record.kind) == "user_turn" and
               String.contains?(record.text || "", "shared color is red")
           end)
  end

  test "capture :off skips conversation writes" do
    runtime = NoCaptureMemoryAgent.runtime_module()
    agent = new_runtime_agent(runtime)
    session = "memory-off-#{System.unique_integer([:positive])}"

    {:ok, agent, _action} =
      runtime.on_before_cmd(
        agent,
        {:ai_react_start,
         %{
           query: "Remember that I like coffee.",
           request_id: "req-memory-off-1",
           tool_context: %{session: session}
         }}
      )

    agent = Jido.AI.Request.complete_request(agent, "req-memory-off-1", "I will not store this.")

    assert {:ok, agent, []} =
             runtime.on_after_cmd(agent, {:ai_react_start, %{request_id: "req-memory-off-1"}}, [])

    assert {:ok, _agent, {:ai_react_start, params}} =
             runtime.on_before_cmd(
               agent,
               {:ai_react_start,
                %{
                  query: "What drink do I like?",
                  request_id: "req-memory-off-2",
                  tool_context: %{session: session}
                }}
             )

    assert params.tool_context[:memory].records == []
  end

  test "rejects public tool_context in favor of context" do
    assert {:error, {:invalid_option, :tool_context, :use_context}} =
             Moto.Agent.prepare_chat_opts([tool_context: %{actor: %{id: "user-1"}}], nil)
  end

  test "rejects public tool_context in chat helpers" do
    assert {:ok, pid} = ChatAgent.start_link(id: "invalid-tool-context-chat-test")

    try do
      assert {:error, {:invalid_option, :tool_context, :use_context}} =
               ChatAgent.chat(pid, "Hello", tool_context: %{tenant: "acme"})

      assert {:error, {:invalid_option, :tool_context, :use_context}} =
               Moto.chat(pid, "Hello", tool_context: %{tenant: "acme"})
    after
      :ok = Moto.stop_agent(pid)
    end
  end
end
