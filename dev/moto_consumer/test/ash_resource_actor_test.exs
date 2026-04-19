defmodule MotoConsumer.AshResourceActorTest do
  use ExUnit.Case, async: false

  alias MotoConsumer.Accounts
  alias MotoConsumer.Accounts.SecureNote
  alias MotoConsumer.SupportNoteAgent

  test "AshJido create succeeds when actor comes from scope" do
    actor = %{id: "scope_actor", name: "Scope User"}

    assert {:ok, note} =
             SecureNote.Jido.Create.run(
               %{title: "Scoped Secret", owner_id: actor.id},
               %{domain: Accounts, scope: %{actor: actor}}
             )

    assert note.title == "Scoped Secret"
    assert note.owner_id == "scope_actor"
  end

  test "AshJido create fails without actor or scope" do
    assert {:error, error} =
             SecureNote.Jido.Create.run(
               %{title: "Denied"},
               %{domain: Accounts, actor: nil}
             )

    assert error.details.reason == :forbidden
  end

  test "Moto ash_resource agents do not supply a default actor" do
    assert SupportNoteAgent.requires_actor?()

    assert {:ok, pid} = SupportNoteAgent.start_link(id: "support-note-agent")

    try do
      assert {:error, {:missing_tool_context, :actor}} =
               SupportNoteAgent.chat(pid, "List secure notes.")

      assert {:error, {:missing_tool_context, :actor}} =
               SupportNoteAgent.chat(
                 pid,
                 "List secure notes.",
                 tool_context: %{scope: %{actor: %{id: "scope_only"}}}
               )
    after
      :ok = Moto.stop_agent(pid)
    end
  end
end
