defmodule MotoTest.SkillsMCPTest do
  use MotoTest.Support.Case, async: false

  alias MotoTest.{FakeMCPSync, LocalFSMCPAgent, MCPAgent, RuntimeSkillAgent, SkillAgent}

  @mcp_sandbox Path.expand("../../tmp/mcp-sandbox", __DIR__)

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

  @tag :mcp_live
  test "live filesystem MCP endpoint syncs tools into a running Moto agent" do
    prepare_mcp_sandbox!()

    {:ok, pid} = LocalFSMCPAgent.start_link(id: "local-fs-mcp-agent-test")

    on_exit(fn ->
      Moto.stop_agent(pid)
    end)

    assert LocalFSMCPAgent.mcp_tools() == [%{endpoint: :local_fs, prefix: "fs_"}]

    assert {:ok, result} = capture_mcp_logs(fn -> sync_filesystem_tools(pid) end)

    assert result.discovered_count > 0
    assert result.registered_count > 0
    assert "fs_read_text_file" in result.registered_tools
    assert "fs_list_directory" in result.registered_tools
    assert Enum.any?(result.registered_tools, &String.starts_with?(&1, "fs_"))

    {:ok, %{agent: agent}} = Jido.AgentServer.state(pid)

    action_names =
      agent
      |> get_in([Access.key(:state), Access.key(:__strategy__), Access.key(:config)])
      |> Map.fetch!(:actions_by_name)
      |> Map.keys()

    assert Enum.any?(action_names, &String.starts_with?(&1, "fs_"))
    assert "fs_read_text_file" in action_names
    assert "fs_list_directory" in action_names
  end

  defp prepare_mcp_sandbox! do
    File.rm_rf!(@mcp_sandbox)
    File.mkdir_p!(@mcp_sandbox)
    File.write!(Path.join(@mcp_sandbox, "hello.txt"), "hello from Moto MCP test\n")
  end

  defp capture_mcp_logs(fun) do
    ref = make_ref()
    test_pid = self()

    capture_log(fn ->
      send(test_pid, {ref, fun.()})
    end)

    receive do
      {^ref, result} -> result
    after
      0 -> flunk("MCP sync did not return")
    end
  end

  defp sync_filesystem_tools(pid, attempts \\ 10)

  defp sync_filesystem_tools(pid, attempts) do
    case Moto.MCP.SyncToolsToAgent.run(sync_params(pid), %{}) do
      {:ok, _result} = ok ->
        ok

      {:error, _reason} when attempts > 1 ->
        Process.sleep(250)
        sync_filesystem_tools(pid, attempts - 1)

      error ->
        error
    end
  end

  defp sync_params(pid) do
    %{
      endpoint_id: :local_fs,
      agent_server: pid,
      prefix: "fs_",
      replace_existing: false
    }
  end
end
