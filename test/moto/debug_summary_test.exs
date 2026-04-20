defmodule MotoTest.DebugSummaryTest do
  use MotoTest.Support.Case, async: false

  alias Jido.AI.Request

  test "summarizes a completed request from Moto request metadata" do
    agent = new_runtime_agent(MotoTest.ToolAgent.runtime_module())
    request_id = "req-debug-summary-1"

    agent =
      agent
      |> Request.start_request(request_id, "original prompt")
      |> Request.complete_request(
        request_id,
        "42",
        meta: %{
          usage: %{input: 123, output: 45, total_cost: 0.00123},
          moto_hooks: %{
            message: "Use the add_numbers tool to add 17 and 25. Reply with only the sum.",
            context: %{
              Moto.Subagent.request_id_key() => "internal",
              session: "cli",
              tenant: "demo"
            }
          },
          moto_memory: %{
            namespace: "agent:demo",
            records: [%{id: 1}, %{id: 2}],
            config: %{inject: :system_prompt},
            captured?: true
          },
          moto_debug: %{
            system_prompt: "You are a concise assistant. Reply with only the final answer.",
            tool_names: ["add_numbers"],
            message_count: 2
          },
          moto_subagents: %{
            calls: [
              %{
                name: "research_agent",
                mode: :ephemeral,
                child_id: "moto-subagent-1",
                duration_ms: 123,
                task_preview: "Explain vector databases",
                child_result_meta: %{status: :completed}
              }
            ]
          }
        }
      )

    {:ok, summary} = Moto.Debug.request_summary(agent, request_id)

    assert summary.request_id == request_id
    assert summary.status == :completed
    assert summary.model == agent.state.model
    assert summary.input_message == "original prompt"

    assert summary.user_message ==
             "Use the add_numbers tool to add 17 and 25. Reply with only the sum."

    assert summary.system_prompt ==
             "You are a concise assistant. Reply with only the final answer."

    assert summary.tool_names == ["add_numbers"]
    assert summary.context_preview == ["session=\"cli\"", "tenant=\"demo\""]
    assert summary.message_count == 2

    assert summary.memory == %{
             namespace: "agent:demo",
             retrieved: 2,
             inject: :system_prompt,
             captured: true
           }

    assert summary.subagents == [
             %{
               name: "research_agent",
               mode: :ephemeral,
               child_id: "moto-subagent-1",
               duration_ms: 123,
               task_preview: "Explain vector databases",
               child_result_meta: %{status: :completed}
             }
           ]

    assert summary.usage == %{input: 123, output: 45, total: nil, cost: 0.00123}
    assert is_integer(summary.duration_ms)
  end

  test "merges pending prompt previews for a live request" do
    {:ok, pid} = MotoTest.ToolAgent.start_link(id: "debug-summary-live")

    try do
      request_id = "req-debug-summary-live-1"

      :sys.replace_state(pid, fn state ->
        %{state | agent: Request.start_request(state.agent, request_id, "live prompt")}
      end)

      Moto.Debug.record_prompt_preview(
        %{
          Moto.Subagent.server_key() => pid,
          Moto.Subagent.request_id_key() => request_id
        },
        "You are a concise assistant. Use the add_numbers tool.",
        %{
          messages: [%{role: :user, content: "live prompt"}],
          tools: %{"add_numbers" => %{name: "add_numbers"}}
        }
      )

      {:ok, summary} = Moto.Debug.request_summary(pid)

      assert summary.request_id == request_id
      assert summary.status == :pending
      assert summary.system_prompt == "You are a concise assistant. Use the add_numbers tool."
      assert summary.tool_names == ["add_numbers"]
      assert summary.message_count == 1
      assert summary.input_message == "live prompt"
    after
      :ok = Moto.stop_agent(pid)
    end
  end
end
