defmodule MotoTest.AgentBasicsTest do
  use MotoTest.Support.Case, async: false

  alias MotoTest.{
    ChatAgent,
    ContextAgent,
    InlineMapModelAgent,
    MemoryAgent,
    MfaPromptAgent,
    ModulePromptAgent,
    PromptCallbacks,
    StringModelAgent,
    StructModelAgent,
    TenantPrompt
  }

  test "starts a moto agent under the shared runtime" do
    assert {:ok, pid} = ChatAgent.start_link(id: "chat-agent-test")
    assert is_pid(pid)
    assert Moto.whereis("chat-agent-test") == pid
    assert [{id, ^pid}] = Moto.list_agents()
    assert id == "chat-agent-test"
    assert :ok = Moto.stop_agent(pid)
  end

  test "defaults the agent name from the module" do
    assert ChatAgent.name() == "chat_agent"
    assert ChatAgent.runtime_module() == MotoTest.ChatAgent.Runtime
  end

  test "exposes the configured system prompt" do
    assert ChatAgent.system_prompt() == "You are a concise assistant."
    assert ChatAgent.request_transformer() == nil
  end

  test "exposes the configured default context" do
    assert ContextAgent.context() == %{tenant: "demo", channel: "test"}
  end

  test "exposes the configured memory settings" do
    assert MemoryAgent.memory() == %{
             mode: :conversation,
             namespace: {:context, :session},
             capture: :conversation,
             retrieve: %{limit: 4},
             inject: :system_prompt
           }

    assert ChatAgent.memory() == nil
  end

  test "supports module-based dynamic system prompts" do
    assert ModulePromptAgent.system_prompt() == TenantPrompt

    assert ModulePromptAgent.request_transformer() ==
             MotoTest.ModulePromptAgent.RuntimeRequestTransformer

    request = react_request([%{role: :user, content: "hello"}])
    state = react_state()
    config = react_config(ModulePromptAgent.request_transformer())

    assert {:ok, %{messages: messages}} =
             ModulePromptAgent.request_transformer().transform_request(
               request,
               state,
               config,
               %{tenant: "acme"}
             )

    assert messages == [
             %{role: :system, content: "You are helping tenant acme."},
             %{role: :user, content: "hello"}
           ]
  end

  test "supports MFA-based dynamic system prompts" do
    assert MfaPromptAgent.system_prompt() == {PromptCallbacks, :build, ["Serve tenant"]}

    assert MfaPromptAgent.request_transformer() ==
             MotoTest.MfaPromptAgent.RuntimeRequestTransformer

    request =
      react_request([%{role: :system, content: "stale"}, %{role: :user, content: "hello"}])

    state = react_state()
    config = react_config(MfaPromptAgent.request_transformer())

    assert {:ok, %{messages: messages}} =
             MfaPromptAgent.request_transformer().transform_request(
               request,
               state,
               config,
               %{"tenant" => "beta"}
             )

    assert messages == [
             %{role: :system, content: "Serve tenant beta."},
             %{role: :user, content: "hello"}
           ]
  end

  test "appends retrieved memory to the effective system prompt" do
    assert MemoryAgent.request_transformer() == MotoTest.MemoryAgent.RuntimeRequestTransformer

    request = react_request([%{role: :user, content: "hello"}])
    state = react_state()
    config = react_config(MemoryAgent.request_transformer())

    assert {:ok, %{messages: messages}} =
             MemoryAgent.request_transformer().transform_request(
               request,
               state,
               config,
               %{
                 Moto.Memory.context_key() => %{
                   prompt: "Relevant memory:\n- User: My favorite color is blue."
                 }
               }
             )

    assert messages == [
             %{
               role: :system,
               content:
                 "You have conversation memory.\n\nRelevant memory:\n- User: My favorite color is blue."
             },
             %{role: :user, content: "hello"}
           ]
  end

  test "resolves Moto-owned aliases and falls back to Jido.AI aliases" do
    assert Moto.model_aliases()[:fast] == "anthropic:claude-haiku-4-5"
    assert Moto.model(:fast) == "anthropic:claude-haiku-4-5"
    assert Moto.model(:capable) == Jido.AI.resolve_model(:capable)
    assert ChatAgent.configured_model() == :fast
    assert ChatAgent.model() == "anthropic:claude-haiku-4-5"
  end

  test "passes through direct model strings" do
    assert StringModelAgent.configured_model() == "openai:gpt-4.1"
    assert StringModelAgent.model() == "openai:gpt-4.1"
  end

  test "passes through inline model maps" do
    expected = %{provider: :openai, id: "gpt-4.1", base_url: "http://localhost:4000/v1"}

    assert InlineMapModelAgent.configured_model() == expected
    assert InlineMapModelAgent.model() == expected
  end

  test "passes through %LLMDB.Model{} structs" do
    assert %LLMDB.Model{id: "gpt-4.1", provider: :openai} = StructModelAgent.configured_model()
    assert %LLMDB.Model{id: "gpt-4.1", provider: :openai} = StructModelAgent.model()
  end

  test "Moto.chat returns not_found for missing ids" do
    assert {:error, :not_found} = Moto.chat("missing-agent-id", "hello")
  end
end
