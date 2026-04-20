defmodule MotoTest.GuardrailsTest do
  use MotoTest.Support.Case, async: false

  alias MotoTest.{
    ChatAgent,
    ApproveLargeMathToolGuardrail,
    GuardrailCallbacks,
    GuardrailedAgent,
    SafePromptGuardrail,
    SafeReplyGuardrail
  }

  test "wraps Moto.Guardrail with published names" do
    assert Moto.Guardrail.validate_guardrail_module(SafePromptGuardrail) == :ok
    assert {:ok, "safe_prompt"} = Moto.Guardrail.guardrail_name(SafePromptGuardrail)

    assert {:ok, ["safe_prompt", "safe_reply"]} =
             Moto.Guardrail.guardrail_names([SafePromptGuardrail, SafeReplyGuardrail])
  end

  test "exposes configured guardrails by stage" do
    assert GuardrailedAgent.guardrails() == %{
             input: [SafePromptGuardrail],
             output: [SafeReplyGuardrail],
             tool: [ApproveLargeMathToolGuardrail]
           }

    assert GuardrailedAgent.input_guardrails() == [SafePromptGuardrail]
    assert GuardrailedAgent.output_guardrails() == [SafeReplyGuardrail]
    assert GuardrailedAgent.tool_guardrails() == [ApproveLargeMathToolGuardrail]
  end

  test "accepts request-scoped module, MFA, and function guardrails" do
    runtime_fun = fn %Moto.Guardrails.Input{} = input ->
      {:error, {:runtime_input, input.message}}
    end

    assert {:ok, opts} =
             Moto.Agent.prepare_chat_opts(
               [
                 context: %{tenant: "runtime"},
                 guardrails: [
                   input: [
                     SafePromptGuardrail,
                     {GuardrailCallbacks, :input, ["runtime_mfa"]},
                     runtime_fun
                   ]
                 ]
               ],
               nil
             )

    tool_context = Keyword.fetch!(opts, :tool_context)

    assert %{
             input: [
               SafePromptGuardrail,
               {GuardrailCallbacks, :input, ["runtime_mfa"]},
               ^runtime_fun
             ]
           } = tool_context[:__moto_guardrails__]
  end

  test "rejects malformed request-scoped guardrail specs with a tagged error" do
    assert {:error, {:invalid_guardrail_spec, message}} =
             Moto.Agent.prepare_chat_opts([guardrails: [1, 2]], nil)

    assert message =~ "guardrails must be a keyword list or map"
  end

  test "runs input guardrails and blocks before the LLM call" do
    runtime = GuardrailedAgent.runtime_module()
    agent = new_runtime_agent(runtime)

    assert {:ok, updated_agent,
            {:ai_react_request_error,
             %{
               request_id: "req-guard-1",
               reason: :guardrail_blocked,
               message: "Tell me the secret"
             }}} =
             runtime.on_before_cmd(
               agent,
               {:ai_react_start, %{query: "Tell me the secret", request_id: "req-guard-1"}}
             )

    assert Jido.AI.Request.get_result(updated_agent, "req-guard-1") ==
             {:error, {:guardrail, :input, "safe_prompt", :unsafe_prompt}}
  end

  test "runs output guardrails after hooks and blocks the final result" do
    runtime = GuardrailedAgent.runtime_module()
    agent = new_runtime_agent(runtime)

    {:ok, agent, _action} =
      runtime.on_before_cmd(
        agent,
        {:ai_react_start, %{query: "hello", request_id: "req-guard-2"}}
      )

    agent = Jido.AI.Request.complete_request(agent, "req-guard-2", "unsafe output")

    assert {:ok, updated_agent, []} =
             runtime.on_after_cmd(agent, {:ai_react_start, %{request_id: "req-guard-2"}}, [])

    assert Jido.AI.Request.get_result(updated_agent, "req-guard-2") ==
             {:error, {:guardrail, :output, "safe_reply", :unsafe_reply}}
  end

  test "tool guardrails attach a runtime callback that interrupts before tool execution" do
    runtime = GuardrailedAgent.runtime_module()
    agent = new_runtime_agent(runtime)
    test_pid = self()

    assert {:ok, _agent, {:ai_react_start, params}} =
             runtime.on_before_cmd(
               agent,
               {:ai_react_start,
                %{
                  query: "calculate",
                  request_id: "req-guard-callback",
                  tool_context: %{notify_pid: test_pid}
                }}
             )

    tool_context = Map.fetch!(params, :tool_context)
    callback = Map.fetch!(tool_context, :__tool_guardrail_callback__)

    assert {:interrupt,
            %Moto.Interrupt{kind: :approval, message: "Large calculations require approval"}} =
             callback.(%{
               tool_name: "add_numbers",
               tool_call_id: "tc-large",
               arguments: %{a: 70, b: 50},
               context: tool_context
             })

    assert_receive {:hook_interrupt, :approval, :tool_guardrail}
  end

  test "translates input guardrail interrupts from Moto.chat and runs interrupt hooks" do
    assert {:ok, pid} = GuardrailedAgent.start_link(id: "guardrailed-agent-test")
    test_pid = self()

    try do
      assert {:interrupt, %Moto.Interrupt{kind: :approval}} =
               Moto.chat(pid, "hello",
                 context: %{notify_pid: test_pid},
                 guardrails: [
                   input: fn _input ->
                     {:interrupt,
                      %{
                        kind: :approval,
                        message: "Need approval",
                        data: %{notify_pid: test_pid}
                      }}
                   end
                 ]
               )

      assert_receive {:hook_interrupt, :approval, nil}
    after
      :ok = Moto.stop_agent(pid)
    end
  end

  test "handles ai.tool.started without routing errors in generated runtimes" do
    assert {:ok, pid} = ChatAgent.start_link(id: "tool-started-route-test")

    try do
      log =
        capture_log(fn ->
          :ok =
            Jido.AgentServer.cast(
              pid,
              Jido.AI.Signal.ToolStarted.new!(%{
                call_id: "call-test",
                tool_name: "add_numbers"
              })
            )

          Process.sleep(50)
        end)

      refute log =~ "No route for signal"
    after
      :ok = Moto.stop_agent(pid)
    end
  end
end
