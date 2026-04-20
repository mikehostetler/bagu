defmodule MotoTest.AshResourceTest do
  use MotoTest.Support.Case, async: false

  test "expands ash_resource into generated AshJido action modules" do
    assert AshResourceAgent.ash_resources() == [User]
    assert AshResourceAgent.ash_domain() == Accounts
    assert AshResourceAgent.requires_actor?()
    assert Enum.sort(AshResourceAgent.tool_names()) == ["create_user", "list_users"]

    assert Enum.any?(AshResourceAgent.tools(), &(&1 == MotoTest.Support.User.Jido.Create))
    assert Enum.any?(AshResourceAgent.tools(), &(&1 == MotoTest.Support.User.Jido.Read))
  end

  test "requires actor in context for ash_resource agents" do
    assert {:ok, pid} = AshResourceAgent.start_link(id: "ash-resource-agent-test")

    try do
      assert {:error, {:missing_context, :actor}} =
               AshResourceAgent.chat(pid, "List users.")
    after
      :ok = Moto.stop_agent(pid)
    end
  end

  test "injects ash domain into internal tool_context for ash_resource agents" do
    assert {:ok, opts} =
             Moto.Agent.prepare_chat_opts(
               [context: %{actor: %{id: "user-1"}}],
               %{domain: Accounts, require_actor?: true}
             )

    assert Keyword.get(opts, :tool_context) == %{actor: %{id: "user-1"}, domain: Accounts}
  end

  test "rejects mismatched context domain for ash_resource agents" do
    assert {:error, {:invalid_context, {:domain_mismatch, Accounts, :other_domain}}} =
             Moto.Agent.prepare_chat_opts(
               [context: %{actor: %{id: "user-1"}, domain: :other_domain}],
               %{domain: Accounts, require_actor?: true}
             )
  end
end
