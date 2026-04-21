defmodule MotoTest.InspectionTest do
  use MotoTest.Support.Case, async: false

  alias Jido.AI.Request
  alias MotoTest.AddNumbers

  test "inspects a compiled Moto agent module" do
    assert {:ok, definition} = Moto.inspect_agent(MotoTest.ToolAgent)

    assert definition.kind == :agent_definition
    assert definition.module == MotoTest.ToolAgent
    assert definition.runtime_module == MotoTest.ToolAgent.runtime_module()
    assert definition.name == "tool_agent"
    assert definition.tool_names == ["add_numbers"]
    assert definition.plugins == []
  end

  test "inspects an imported Moto agent definition" do
    assert {:ok, agent} =
             Moto.import_agent(
               %{
                 "name" => "inspect_imported",
                 "model" => "fast",
                 "system_prompt" => "You are concise.",
                 "tools" => ["add_numbers"]
               },
               available_tools: [AddNumbers]
             )

    assert {:ok, definition} = Moto.inspect_agent(agent)

    assert definition.kind == :imported_agent_definition
    assert definition.module == nil
    assert definition.name == "inspect_imported"
    assert definition.tool_names == ["add_numbers"]
    assert definition.runtime_module == agent.runtime_module
  end

  test "inspects a running Moto agent and includes the latest request summary" do
    {:ok, pid} = MotoTest.ToolAgent.start_link(id: "inspect-running-tool-agent")

    try do
      request_id = "req-inspect-running-1"

      :sys.replace_state(pid, fn state ->
        request =
          state.agent
          |> Request.start_request(request_id, "inspect this")
          |> Request.complete_request(
            request_id,
            "42",
            meta: %{
              moto_debug: %{
                system_prompt: "You can use math tools.",
                tool_names: ["add_numbers"],
                message_count: 1
              }
            }
          )

        %{state | agent: request}
      end)

      assert {:ok, inspection} = Moto.inspect_agent(pid)

      assert inspection.kind == :running_agent
      assert inspection.runtime_module == MotoTest.ToolAgent.runtime_module()
      assert inspection.definition.name == "tool_agent"
      assert inspection.definition.tool_names == ["add_numbers"]
      assert inspection.last_request_id == request_id
      assert inspection.last_request.input_message == "inspect this"
    after
      :ok = Moto.stop_agent(pid)
    end
  end

  test "inspects a request summary directly" do
    agent = new_runtime_agent(MotoTest.ToolAgent.runtime_module())
    request_id = "req-inspect-summary-1"

    agent =
      agent
      |> Request.start_request(request_id, "original prompt")
      |> Request.complete_request(
        request_id,
        "42",
        meta: %{
          usage: %{input: 10, output: 2},
          moto_debug: %{
            system_prompt: "You can use math tools.",
            tool_names: ["add_numbers"],
            message_count: 1
          }
        }
      )

    assert {:ok, summary} = Moto.inspect_request(agent, request_id)
    assert summary.request_id == request_id
    assert summary.system_prompt == "You can use math tools."
    assert summary.tool_names == ["add_numbers"]
    assert summary.usage == %{input: 10, output: 2, total: nil, cost: nil}
  end
end
