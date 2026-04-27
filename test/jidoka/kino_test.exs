defmodule JidokaTest.KinoTest do
  use JidokaTest.Support.Case, async: false

  require Logger

  test "trace returns the wrapped result without Kino loaded" do
    result =
      Jidoka.Kino.trace("smoke", fn ->
        Logger.notice("Executing Jido.Actions.Control.Noop with params: %{query: \"hello\"}")
        :ok
      end)

    assert result == :ok
  end

  test "load_provider_env mirrors Livebook secret names" do
    previous_anthropic = System.get_env("ANTHROPIC_API_KEY")
    previous_livebook = System.get_env("LB_ANTHROPIC_API_KEY")

    System.delete_env("ANTHROPIC_API_KEY")
    System.put_env("LB_ANTHROPIC_API_KEY", "livebook-secret")

    try do
      assert Jidoka.Kino.load_provider_env() == {:ok, "LB_ANTHROPIC_API_KEY"}
      assert System.get_env("ANTHROPIC_API_KEY") == "livebook-secret"
    after
      restore_env("ANTHROPIC_API_KEY", previous_anthropic)
      restore_env("LB_ANTHROPIC_API_KEY", previous_livebook)
    end
  end

  test "start_or_reuse starts once and reuses a registered agent" do
    id = "kino-reuse-#{System.unique_integer([:positive])}"
    test_pid = self()

    try do
      assert {:ok, pid} =
               Jidoka.Kino.start_or_reuse(id, fn ->
                 send(test_pid, :started)
                 JidokaTest.ChatAgent.start_link(id: id)
               end)

      assert_receive :started

      assert {:ok, ^pid} =
               Jidoka.Kino.start_or_reuse(id, fn ->
                 flunk("existing agent should be reused")
               end)
    after
      case Jidoka.whereis(id) do
        nil -> :ok
        pid -> Jidoka.stop_agent(pid)
      end
    end
  end

  test "chat returns a missing provider error before calling the provider" do
    previous_anthropic = System.get_env("ANTHROPIC_API_KEY")
    previous_livebook = System.get_env("LB_ANTHROPIC_API_KEY")

    System.delete_env("ANTHROPIC_API_KEY")
    System.delete_env("LB_ANTHROPIC_API_KEY")

    try do
      result =
        Jidoka.Kino.chat("missing provider", fn ->
          flunk("chat function should not run without provider configuration")
        end)

      assert {:error, message} = result
      assert message =~ "ANTHROPIC_API_KEY"
    after
      restore_env("ANTHROPIC_API_KEY", previous_anthropic)
      restore_env("LB_ANTHROPIC_API_KEY", previous_livebook)
    end
  end

  test "format_chat_result presents handoffs as notebook-friendly summaries" do
    handoff =
      Jidoka.Handoff.new(
        id: "handoff-1",
        conversation_id: "conversation-1",
        from_agent: "router",
        to_agent: JidokaTest.ChatAgent,
        to_agent_id: "billing-agent",
        name: "billing_agent",
        message: "Billing should own the next turn.",
        summary: "Invoice dispute.",
        reason: "billing",
        context: %{tenant: "acme"}
      )

    assert {:handoff, summary} = Jidoka.Kino.format_chat_result({:handoff, handoff})
    assert summary.to_agent_id == "billing-agent"
    assert summary.context_keys == ["tenant"]

    assert {:handoff, nested_summary} = Jidoka.Kino.format_chat_result({:error, {:handoff, handoff}})
    assert nested_summary.name == "billing_agent"
  end

  test "format_chat_result presents interrupts as notebook-friendly summaries" do
    interrupt =
      Jidoka.Interrupt.new(
        id: "interrupt-1",
        kind: :approval,
        message: "Approve the large calculation.",
        data: %{tool: "add_numbers"}
      )

    assert {:interrupt, summary} = Jidoka.Kino.format_chat_result({:interrupt, interrupt})
    assert summary.kind == :approval
    assert summary.data_keys == ["tool"]

    assert {:interrupt, nested_summary} = Jidoka.Kino.format_chat_result({:error, {:interrupt, interrupt}})
    assert nested_summary.message == "Approve the large calculation."
  end

  test "debug_agent renders and returns an inspection summary without Kino loaded" do
    assert {:ok, inspection} = Jidoka.Kino.debug_agent(JidokaTest.ToolAgent)

    assert inspection.kind == :agent_definition
    assert inspection.tool_names == ["add_numbers"]
  end

  test "agent_diagram renders and returns Mermaid markdown without Kino loaded" do
    assert {:ok, markdown} = Jidoka.Kino.agent_diagram(JidokaTest.ToolAgent)

    assert markdown =~ "flowchart LR"
    assert markdown =~ "tool_agent"
    assert markdown =~ "add_numbers"
  end

  test "context renders public and internal runtime keys without Kino loaded" do
    assert :ok =
             Jidoka.Kino.context("runtime context", %{
               Jidoka.Subagent.request_id_key() => "req-1",
               "__tool_guardrail_callback__" => :callback,
               tenant: "acme"
             })
  end

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)
end
