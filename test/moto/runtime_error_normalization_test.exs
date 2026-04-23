defmodule MotoTest.RuntimeErrorNormalizationTest do
  use MotoTest.Support.Case, async: false

  @moduletag :capture_log

  alias Jido.AI.Request

  alias MotoTest.{
    ChatAgent,
    FailingMCPSync,
    GuardrailedAgent,
    MemoryAgent,
    MissingPeerOrchestratorAgent,
    OrchestratorAgent
  }

  alias MotoTest.Workflow.FailingWorkflow

  setup do
    previous_sync_module = Application.get_env(:moto, :mcp_sync_module)

    on_exit(fn ->
      if previous_sync_module do
        Application.put_env(:moto, :mcp_sync_module, previous_sync_module)
      else
        Application.delete_env(:moto, :mcp_sync_module)
      end
    end)

    :ok
  end

  test "Moto.chat wraps missing runtime ids" do
    assert {:error, %Moto.Error.ValidationError{} = error} =
             Moto.chat("missing-runtime-normalization-agent", "hello")

    assert error.details.operation == :chat
    assert error.details.reason == :not_found
    assert error.details.cause == :not_found
    assert Moto.format_error(error) == "Moto agent could not be found."
  end

  test "prepare_chat_opts wraps malformed request hook specs" do
    assert {:error, %Moto.Error.ValidationError{} = error} =
             Moto.Agent.prepare_chat_opts([hooks: [1, 2]], nil)

    assert error.details.operation == :prepare_chat_opts
    assert error.details.reason == :invalid_hook_spec
    assert is_binary(error.details.cause)
  end

  test "workflow failures preserve the raw cause" do
    assert {:error, %Moto.Error.ExecutionError{} = error} =
             FailingWorkflow.run(%{reason: "normalized boom"})

    assert error.details.workflow_id == "failing_workflow"
    assert error.details.step == :fail
    assert error.details.cause == "normalized boom"
    assert Moto.format_error(error) == "Workflow failing_workflow step fail failed."
  end

  test "subagent tools wrap peer lookup failures" do
    tool = find_tool(MissingPeerOrchestratorAgent, "research_agent")

    assert {:error, %Moto.Error.ExecutionError{} = error} =
             tool.run(%{task: "Find peer"}, %{})

    assert error.details.operation == :subagent
    assert error.details.agent_id == "research_agent"
    assert error.details.reason == :peer_not_found
    assert error.details.cause == {:peer_not_found, "missing-peer-test"}
  end

  test "MCP sync wraps command failures at the public helper boundary" do
    Application.put_env(:moto, :mcp_sync_module, FailingMCPSync)

    with_isolated_mcp_pool(fn ->
      assert {:error, %Moto.Error.ExecutionError{} = error} =
               Moto.MCP.sync_tools(
                 self(),
                 [endpoint: :runtime_error_sync, prefix: "err_", replace_existing: false] ++
                   runtime_endpoint_attrs()
               )

      assert error.details.operation == :mcp
      assert error.details.cause == :server_capabilities_not_set
      assert Moto.format_error(error) == "MCP operation failed."
    end)
  end

  test "memory retrieval failures are hard structured request errors" do
    runtime = MemoryAgent.runtime_module()
    agent = new_runtime_agent(runtime)

    assert {:ok, updated_agent,
            {:ai_react_request_error, %{request_id: "req-memory-normalized", reason: :memory_failed}}} =
             runtime.on_before_cmd(
               agent,
               {:ai_react_start, %{query: "remember", request_id: "req-memory-normalized", tool_context: %{}}}
             )

    assert {:error, %Moto.Error.ValidationError{} = error} =
             Request.get_result(updated_agent, "req-memory-normalized")

    assert error.details.reason == :missing_context
    assert error.details.key == :session
    assert Moto.format_error(error) =~ "Missing required context key `session`"
  end

  test "memory capture failures are soft structured warnings" do
    error = Moto.Error.Normalize.memory_error(:capture, :write_failed, agent_id: "memory_agent")

    assert %Moto.Error.ExecutionError{} = error
    assert error.details.phase == :memory_capture
    assert error.details.cause == :write_failed
    assert Moto.format_error(error) == "Moto memory capture failed."
  end

  test "hook callback failures return structured execution errors" do
    assert {:ok, pid} = ChatAgent.start_link(id: "runtime-hook-error-normalization")

    try do
      bad_hook = fn _input -> {:ok, [1, 2]} end

      assert {:error, %Moto.Error.ExecutionError{} = error} =
               Moto.chat(pid, "hello", hooks: [before_turn: bad_hook])

      assert error.details.operation == :hook
      assert error.details.stage == :before_turn
      assert error.details.cause =~ "before_turn hook must return"
    after
      :ok = Moto.stop_agent(pid)
    end
  end

  test "guardrail blocks return structured execution errors" do
    assert {:ok, pid} = GuardrailedAgent.start_link(id: "runtime-guardrail-error-normalization")

    try do
      assert {:error, %Moto.Error.ExecutionError{} = error} =
               Moto.chat(pid, "hello", guardrails: [input: fn _input -> {:error, :blocked_for_test} end])

      assert error.details.operation == :guardrail
      assert error.details.stage == :input
      assert error.details.label == "anonymous_guardrail"
      assert error.details.cause == :blocked_for_test
    after
      :ok = Moto.stop_agent(pid)
    end
  end

  test "subagent validation errors are structured" do
    assert {:error, %Moto.Error.ValidationError{} = error} =
             Moto.Subagent.run_subagent(
               hd(OrchestratorAgent.subagents()),
               %{task: ""},
               %{}
             )

    assert error.details.operation == :subagent
    assert error.details.reason == :invalid_task
    assert error.details.cause == {:invalid_task, :expected_non_empty_string}
  end

  defp runtime_endpoint_attrs do
    [
      transport: {:stdio, command: "echo"},
      client_info: %{name: "moto-runtime-error-test", version: "0.1.0"},
      timeouts: %{request_ms: 15_000}
    ]
  end

  defp with_isolated_mcp_pool(fun) do
    previous_state = :sys.get_state(Jido.MCP.ClientPool)

    try do
      fun.()
    after
      :sys.replace_state(Jido.MCP.ClientPool, fn _state -> previous_state end)
    end
  end
end
