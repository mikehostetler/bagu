defmodule JidokaTest.AgentViewContractTest do
  use ExUnit.Case, async: true

  defmodule ContractAgent do
    def id, do: "contract_agent"
  end

  defmodule DefaultView do
    use Jidoka.AgentView, agent: ContractAgent
  end

  defmodule CustomView do
    use Jidoka.AgentView

    @impl Jidoka.AgentView
    def agent_module(_input), do: ContractAgent

    @impl Jidoka.AgentView
    def conversation_id(input), do: Jidoka.AgentView.normalize_id(input[:conversation], "demo")

    @impl Jidoka.AgentView
    def agent_id(input), do: "custom-agent-#{conversation_id(input)}"

    @impl Jidoka.AgentView
    def runtime_context(input) do
      %{
        channel: "test",
        session: conversation_id(input),
        account_id: input[:account_id]
      }
    end
  end

  test "default AgentView callbacks derive conversation, agent id, and runtime context" do
    input = %{"conversation_id" => "Case 123!"}

    assert DefaultView.conversation_id(input) == "case_123"
    assert DefaultView.agent_id(input) == "contract_agent-case_123"
    assert DefaultView.runtime_context(input) == %{session: "case_123"}
  end

  test "custom AgentView callbacks define the application surface" do
    input = %{conversation: "VIP Refund", account_id: "acct_123"}

    assert CustomView.agent_module(input) == ContractAgent
    assert CustomView.conversation_id(input) == "vip_refund"
    assert CustomView.agent_id(input) == "custom-agent-vip_refund"

    assert CustomView.runtime_context(input) == %{
             channel: "test",
             session: "vip_refund",
             account_id: "acct_123"
           }
  end

  test "before_turn adds optimistic user state without mutating rendered output concerns" do
    view = Jidoka.AgentView.new(agent_id: "contract-agent", conversation_id: "case_123")

    assert %{status: :idle, visible_messages: []} = DefaultView.before_turn(view, " ")

    running = DefaultView.before_turn(view, "  Need refund help  ")

    assert running.status == :running
    assert running.error == nil
    assert running.error_text == nil
    assert running.streaming_message == nil
    assert [%{role: :user, content: "Need refund help", pending?: true}] = running.visible_messages
  end

  test "compatibility submit alias delegates to before_turn" do
    view = Jidoka.AgentView.new(agent_id: "contract-agent", conversation_id: "case_123")

    submit = DefaultView.before_submit(view, "hello")
    turn = DefaultView.before_turn(view, "hello")

    assert submit.status == turn.status
    assert submit.error == turn.error
    assert submit.error_text == turn.error_text

    assert Enum.map(submit.visible_messages, &Map.drop(&1, [:id])) ==
             Enum.map(turn.visible_messages, &Map.drop(&1, [:id]))
  end

  test "after_turn preserves structured errors and provides formatted text" do
    reason = Jidoka.Error.validation_error("Bad input.", field: :message)
    agent = %Jido.Agent{id: "contract_agent", state: %{}}

    run = %Jidoka.AgentView.Run{
      request: Jido.AI.Request.Handle.new("req-test", self(), "hello"),
      agent_ref: agent,
      request_id: "req-test",
      conversation_id: "case_123",
      view_module: DefaultView,
      input: %{}
    }

    assert {:ok, updated} = DefaultView.after_turn(run, {:error, reason})

    assert updated.status == :error
    assert updated.error == reason
    assert updated.error_text == "Bad input."
    assert updated.outcome == {:error, reason}
  end

  test "visible_messages appends an in-flight streaming draft" do
    view =
      Jidoka.AgentView.new(
        visible_messages: [%{role: :user, content: "Hello"}],
        streaming_message: %{role: :assistant, content: "Working", streaming?: true}
      )

    assert [
             %{role: :user, content: "Hello"},
             %{role: :assistant, content: "Working", streaming?: true}
           ] = DefaultView.visible_messages(view)
  end
end
