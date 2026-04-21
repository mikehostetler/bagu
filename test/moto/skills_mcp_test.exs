defmodule MotoTest.SkillsMCPTest do
  use MotoTest.Support.Case, async: false

  alias MotoTest.{FakeMCPSync, MCPAgent, RuntimeSkillAgent, SkillAgent}

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

  test "module skills contribute action-backed tools to the agent registry" do
    assert SkillAgent.tool_names() == ["multiply_numbers"]
    assert SkillAgent.tools() == [MotoTest.MultiplyNumbers]
  end

  test "module skills append prompt text through the request transformer" do
    agent = new_runtime_agent(SkillAgent.runtime_module())

    assert {:ok, _agent, {:ai_react_start, params}} =
             Moto.Skill.on_before_cmd(
               agent,
               {:ai_react_start, %{query: "Multiply 6 and 7", tool_context: %{tenant: "demo"}}},
               SkillAgent.skills()
             )

    assert params.allowed_tools == ["multiply_numbers"]
    assert params.tool_context[Moto.Skill.context_key()].names == ["module-math-skill"]

    request = react_request([%{role: :user, content: "Multiply 6 and 7"}])
    state = react_state()
    config = react_config(SkillAgent.request_transformer())

    assert {:ok, %{messages: messages}} =
             SkillAgent.request_transformer().transform_request(
               request,
               state,
               config,
               params.tool_context
             )

    assert [%{role: :system, content: system_prompt}, %{role: :user, content: "Multiply 6 and 7"}] =
             messages

    assert system_prompt =~ "You can use skills."
    assert system_prompt =~ "module-math-skill"
    assert system_prompt =~ "multiply_numbers"
  end

  test "runtime skills load from configured paths and narrow allowed tools" do
    agent = new_runtime_agent(RuntimeSkillAgent.runtime_module())

    assert {:ok, _agent, {:ai_react_start, params}} =
             Moto.Skill.on_before_cmd(
               agent,
               {:ai_react_start,
                %{
                  query: "Add 17 and 25",
                  allowed_tools: ["add_numbers", "multiply_numbers"],
                  tool_context: %{}
                }},
               RuntimeSkillAgent.skills()
             )

    assert params.allowed_tools == ["add_numbers"]
    assert params.tool_context[Moto.Skill.context_key()].names == ["math-discipline"]
    assert params.tool_context[Moto.Skill.context_key()].prompt =~ "Math Discipline"
  end

  test "mcp sync runs once per endpoint per agent" do
    Application.put_env(:moto, :mcp_sync_module, FakeMCPSync)

    agent = new_runtime_agent(MCPAgent.runtime_module())

    assert {:ok, agent, {:ai_react_start, %{}}} =
             Moto.MCP.on_before_cmd(agent, {:ai_react_start, %{}}, MCPAgent.mcp_tools())

    assert_received {:mcp_sync_called,
                     %{
                       agent_server: test_pid,
                       endpoint_id: :github,
                       prefix: "github_",
                       replace_existing: false
                     }}

    assert test_pid == self()

    assert {:ok, _agent, {:ai_react_start, %{}}} =
             Moto.MCP.on_before_cmd(agent, {:ai_react_start, %{}}, MCPAgent.mcp_tools())

    refute_received {:mcp_sync_called, _}
  end
end
