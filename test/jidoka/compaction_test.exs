defmodule JidokaTest.CompactionTest do
  use JidokaTest.Support.Case, async: false

  alias Jido.Thread
  alias Jido.Thread.Agent, as: ThreadAgent
  alias Jidoka.Compaction
  alias JidokaTest.{ChatAgent, CompactionAgent, CompactionPrompt, CompactionPromptCallbacks, ManualCompactionAgent}

  setup do
    previous = Application.get_env(:jidoka, :compaction_summarizer)

    on_exit(fn ->
      if is_nil(previous) do
        Application.delete_env(:jidoka, :compaction_summarizer)
      else
        Application.put_env(:jidoka, :compaction_summarizer, previous)
      end
    end)

    :ok
  end

  test "agents expose configured compaction settings" do
    assert %{
             mode: :auto,
             strategy: :summary,
             max_messages: 4,
             keep_last: 2,
             max_summary_chars: 120,
             prompt: "Compact the transcript for this test."
           } = CompactionAgent.compaction()

    assert ChatAgent.compaction() == nil
  end

  test "normalizes prompt overrides and rejects invalid compaction config" do
    assert {:ok, %{prompt: CompactionPrompt}} =
             Compaction.normalize_dsl([%Jidoka.Agent.Dsl.CompactionPrompt{value: CompactionPrompt}])

    assert {:ok, %{prompt: {CompactionPromptCallbacks, :build, ["prefix"]}}} =
             Compaction.normalize_dsl([
               %Jidoka.Agent.Dsl.CompactionPrompt{value: {CompactionPromptCallbacks, :build, ["prefix"]}}
             ])

    assert {:error, reason} =
             Compaction.normalize_dsl([
               %Jidoka.Agent.Dsl.CompactionMaxMessages{value: 2},
               %Jidoka.Agent.Dsl.CompactionKeepLast{value: 2}
             ])

    assert reason =~ "keep_last must be less than max_messages"
  end

  test "auto compaction summarizes old thread messages and attaches runtime context" do
    test_pid = self()

    Application.put_env(:jidoka, :compaction_summarizer, fn input ->
      send(test_pid, {:compaction_input, input.prompt, input.source_message_count, input.retained_message_count})
      {:ok, "summary from #{input.source_message_count} messages"}
    end)

    runtime = CompactionAgent.runtime_module()

    agent =
      runtime
      |> new_runtime_agent()
      |> put_thread([
        ai_message(:user, "old 1", request_id: "req-1"),
        ai_message(:assistant, "old 2", request_id: "req-1"),
        ai_message(:user, "old 3", request_id: "req-2"),
        ai_message(:assistant, "old 4", request_id: "req-2"),
        ai_message(:user, "recent 1", request_id: "req-3"),
        ai_message(:assistant, "recent 2", request_id: "req-3")
      ])

    assert {:ok, updated_agent, {:ai_react_start, params}} =
             runtime.on_before_cmd(
               agent,
               {:ai_react_start,
                %{
                  query: "next",
                  request_id: "req-compact",
                  tool_context: %{conversation_id: "conv-1"}
                }}
             )

    assert_receive {:compaction_input, "Compact the transcript for this test.", 4, 2}

    assert %Compaction{status: :summarized, summary: "summary from 4 messages"} =
             updated_agent.state[Compaction.state_key()]

    assert get_in(params, [:tool_context, Compaction.context_key(), :summary]) == "summary from 4 messages"

    assert get_in(updated_agent.state, [:requests, "req-compact", :meta, :jidoka_compaction, :status]) ==
             :summarized
  end

  test "manual compaction updates a running agent snapshot" do
    {:ok, pid} = ManualCompactionAgent.start_link(id: "manual-compaction-test")

    :sys.replace_state(pid, fn state ->
      agent =
        put_thread(state.agent, [
          ai_message(:user, "old manual 1", request_id: "req-1"),
          ai_message(:assistant, "old manual 2", request_id: "req-1"),
          ai_message(:user, "old manual 3", request_id: "req-2"),
          ai_message(:assistant, "old manual 4", request_id: "req-2"),
          ai_message(:user, "recent manual 1", request_id: "req-3"),
          ai_message(:assistant, "recent manual 2", request_id: "req-3")
        ])

      Jido.AgentServer.State.update_agent(state, agent)
    end)

    assert {:ok, %Compaction{status: :summarized, summary: "manual summary"}} =
             Jidoka.compact(pid, summarizer: fn _input -> {:ok, "manual summary"} end)

    assert {:ok, %Compaction{summary: "manual summary"}} = Jidoka.inspect_compaction(pid)

    :ok = Jidoka.stop_agent(pid)
  end

  test "request transformer injects compaction summary and trims old messages" do
    compaction = %Compaction{
      id: "compaction-test",
      status: :summarized,
      strategy: :summary,
      summary: "Earlier, the user chose billing triage.",
      summary_preview: "Earlier, the user chose billing triage.",
      source_message_count: 2,
      retained_message_count: 2
    }

    request =
      react_request([
        %{role: :system, content: "old system"},
        %{role: :user, content: "old user"},
        %{role: :assistant, content: "old assistant"},
        %{role: :user, content: "new user"},
        %{role: :assistant, content: "new assistant"}
      ])

    assert {:ok, %{messages: messages}} =
             CompactionAgent.request_transformer().transform_request(
               request,
               react_state(),
               react_config(CompactionAgent.request_transformer()),
               %{
                 Compaction.context_key() => %{
                   compaction: compaction,
                   summary: compaction.summary,
                   keep_last: 2
                 }
               }
             )

    assert [
             %{role: :system, content: system_prompt},
             %{role: :user, content: "new user"},
             %{role: :assistant, content: "new assistant"}
           ] = messages

    assert system_prompt =~ "You have compaction."
    assert system_prompt =~ "Compacted conversation summary:"
    assert system_prompt =~ "Earlier, the user chose billing triage."
    refute Enum.any?(messages, &(Map.get(&1, :content) == "old user"))
  end

  test "message trimming preserves tool call and tool result adjacency" do
    context = %{
      Compaction.context_key() => %{
        summary: "tool context exists",
        keep_last: 3
      }
    }

    messages = [
      %{role: :user, content: "old"},
      %{role: :assistant, content: "", tool_calls: [%{id: "call-1", name: "lookup"}]},
      %{role: :tool, content: "result", tool_call_id: "call-1"},
      %{role: :assistant, content: "used result"},
      %{role: :user, content: "next"}
    ]

    assert [
             %{role: :assistant, tool_calls: [_]},
             %{role: :tool, tool_call_id: "call-1"},
             %{role: :assistant, content: "used result"},
             %{role: :user, content: "next"}
           ] = Compaction.apply_to_messages(messages, context)
  end

  test "imported specs round-trip compaction through JSON and YAML" do
    spec = %{
      "agent" => %{"id" => "imported_compaction_agent"},
      "defaults" => %{"model" => "fast", "instructions" => "Use compact context."},
      "lifecycle" => %{
        "compaction" => %{
          "mode" => "auto",
          "strategy" => "summary",
          "max_messages" => 10,
          "keep_last" => 4,
          "max_summary_chars" => 500,
          "prompt" => "Imported compaction prompt."
        }
      }
    }

    assert {:ok, %ImportedAgent{} = agent} = Jidoka.import_agent(spec)
    assert %{mode: :auto, keep_last: 4, prompt: "Imported compaction prompt."} = agent.spec.compaction

    assert {:ok, encoded_json} = Jidoka.encode_agent(agent, format: :json)
    assert encoded_json =~ "\"compaction\""

    assert {:ok, encoded_yaml} = Jidoka.encode_agent(agent, format: :yaml)
    assert encoded_yaml =~ "compaction:"
    assert encoded_yaml =~ "Imported compaction prompt."

    assert {:ok, %ImportedAgent{} = yaml_agent} = Jidoka.import_agent(encoded_yaml, format: :yaml)
    assert %{mode: :auto, keep_last: 4, prompt: "Imported compaction prompt."} = yaml_agent.spec.compaction
  end

  defp put_thread(agent, entries) do
    ThreadAgent.put(agent, Thread.new(id: "thread-compaction") |> Thread.append(entries))
  end

  defp ai_message(role, content, attrs) do
    payload =
      attrs
      |> Map.new()
      |> Map.merge(%{role: role, content: content, context_ref: Keyword.get(attrs, :context_ref, "default")})

    %{
      kind: :ai_message,
      payload: payload,
      refs: %{request_id: Map.get(payload, :request_id)}
    }
  end
end
