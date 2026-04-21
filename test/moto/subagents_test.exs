defmodule MotoTest.SubagentsTest do
  use MotoTest.Support.Case, async: false

  alias MotoTest.{
    ContextPeerOrchestratorAgent,
    OrchestratorAgent,
    PeerOrchestratorAgent,
    ResearchSpecialist,
    ReviewSpecialist,
    WrongPeerOrchestratorAgent
  }

  test "exposes configured subagent definitions and names" do
    assert Enum.map(OrchestratorAgent.subagents(), & &1.name) == [
             "research_agent",
             "review_specialist"
           ]

    assert OrchestratorAgent.subagent_names() == ["research_agent", "review_specialist"]
  end

  test "merges generated subagent tools into the agent tool registry" do
    assert Enum.sort(OrchestratorAgent.tool_names()) == ["research_agent", "review_specialist"]

    assert Enum.all?(OrchestratorAgent.tools(), fn tool_module ->
             String.starts_with?(tool_module.name(), ["research_agent", "review_specialist"])
           end)
  end

  test "runs ephemeral subagents through generated tool modules and forwards public context only" do
    research_tool = find_tool(OrchestratorAgent, "research_agent")

    context = %{
      "tenant" => "acme",
      "notify_pid" => self(),
      "memory" => %{prompt: "should not forward"},
      :__moto_hooks__ => %{before_turn: [:demo]},
      Moto.Subagent.depth_key() => 0
    }

    assert {:ok, %{result: "research:Summarize the issue:tenant=acme:depth=1"}} =
             research_tool.run(%{task: "Summarize the issue"}, context)

    assert_receive {:research_specialist_context, forwarded_context}
    assert forwarded_context["tenant"] == "acme"
    assert forwarded_context["notify_pid"] == self()
    assert forwarded_context[Moto.Subagent.depth_key()] == 1
    refute Map.has_key?(forwarded_context, :memory)
    refute Map.has_key?(forwarded_context, :__moto_hooks__)
  end

  test "supports persistent peer subagents with static ids" do
    assert {:ok, pid} = ResearchSpecialist.start_link(id: "research-peer-test")

    try do
      research_tool = find_tool(PeerOrchestratorAgent, "research_agent")

      assert {:ok, %{result: "research:Investigate the bug:tenant=peer:depth=1"}} =
               research_tool.run(%{task: "Investigate the bug"}, %{tenant: "peer"})

      assert Moto.whereis("research-peer-test") == pid
    after
      :ok = Moto.stop_agent(pid)
    end
  end

  test "supports persistent peer subagents with context-derived ids" do
    assert {:ok, pid} = ResearchSpecialist.start_link(id: "research-peer-ctx-test")

    try do
      research_tool = find_tool(ContextPeerOrchestratorAgent, "research_agent")

      assert {:ok, %{result: "research:Review this report:tenant=ctx:depth=1"}} =
               research_tool.run(
                 %{task: "Review this report"},
                 %{tenant: "ctx", research_peer_id: "research-peer-ctx-test"}
               )
    after
      :ok = Moto.stop_agent(pid)
    end
  end

  test "rejects persistent peers whose runtime module does not match the configured subagent" do
    assert {:ok, pid} = ReviewSpecialist.start_link(id: "wrong-peer-test")

    try do
      research_tool = find_tool(WrongPeerOrchestratorAgent, "research_agent")

      assert {:error,
              {:subagent_failed, "research_agent",
               {:subagent_peer_mismatch, MotoTest.ResearchSpecialist.Runtime,
                MotoTest.ReviewSpecialist.Runtime}}} =
               research_tool.run(%{task: "Validate peer"}, %{})
    after
      :ok = Moto.stop_agent(pid)
    end
  end

  test "enforces the one-hop subagent delegation limit" do
    assert {:error, {:subagent_recursion_limit, 1}} =
             Moto.Subagent.run_subagent(
               hd(OrchestratorAgent.subagents()),
               %{task: "Nested delegation"},
               %{Moto.Subagent.depth_key() => 1}
             )
  end

  test "retains subagent call metadata on the parent request" do
    runtime = OrchestratorAgent.runtime_module()
    agent = new_runtime_agent(runtime)

    assert {:ok, agent, {:ai_react_start, params}} =
             runtime.on_before_cmd(
               agent,
               {:ai_react_start,
                %{
                  query: "delegate",
                  request_id: "req-subagent-meta-1",
                  tool_context: %{tenant: "meta"}
                }}
             )

    research_tool = find_tool(OrchestratorAgent, "research_agent")

    assert {:ok, %{result: "research:Collect notes:tenant=meta:depth=1"}} =
             research_tool.run(%{task: "Collect notes"}, params.tool_context)

    assert {:ok, updated_agent, []} =
             runtime.on_after_cmd(
               agent,
               {:ai_react_start, %{request_id: "req-subagent-meta-1"}},
               []
             )

    assert [%{name: "research_agent", mode: :ephemeral, outcome: :ok}] =
             get_in(updated_agent.state, [
               :requests,
               "req-subagent-meta-1",
               :meta,
               :moto_subagents,
               :calls
             ])
  end

  test "falls back to live subagent metadata when request state has not been updated yet" do
    runtime = OrchestratorAgent.runtime_module()
    agent = new_runtime_agent(runtime)

    assert {:ok, _agent, {:ai_react_start, params}} =
             runtime.on_before_cmd(
               agent,
               {:ai_react_start,
                %{
                  query: "delegate",
                  request_id: "req-subagent-meta-live-1",
                  tool_context: %{tenant: "live"}
                }}
             )

    research_tool = find_tool(OrchestratorAgent, "research_agent")

    assert {:ok, %{result: "research:Collect notes:tenant=live:depth=1"}} =
             research_tool.run(%{task: "Collect notes"}, params.tool_context)

    assert [
             %{
               name: "research_agent",
               mode: :ephemeral,
               outcome: :ok
             }
           ] =
             Moto.Subagent.request_calls(self(), "req-subagent-meta-live-1")
  end

  test "returns recorded subagent calls in invocation order" do
    context = %{
      Moto.Subagent.server_key() => self(),
      Moto.Subagent.request_id_key() => "req-subagent-order-1",
      tenant: "ordered"
    }

    assert {:ok, "review:First delegated task"} =
             Moto.Subagent.run_subagent(
               Enum.at(OrchestratorAgent.subagents(), 1),
               %{task: "First delegated task"},
               context
             )

    assert {:ok, "research:Second delegated task:tenant=ordered:depth=1"} =
             Moto.Subagent.run_subagent(
               hd(OrchestratorAgent.subagents()),
               %{task: "Second delegated task"},
               context
             )

    assert [
             %{name: "review_specialist"},
             %{name: "research_agent"}
           ] = Moto.Subagent.request_calls(self(), "req-subagent-order-1")
  end
end
