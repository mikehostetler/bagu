defmodule MotoTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  alias Moto.DynamicAgent
  alias MotoTest.Support.{Accounts, AshResourceAgent, User}
  alias Jido.AI.Reasoning.ReAct.{Config, State}

  defmodule ChatAgent do
    use Moto.Agent

    agent do
      model(:fast)
      system_prompt("You are a concise assistant.")
    end
  end

  defmodule ContextAgent do
    use Moto.Agent

    agent do
      model(:fast)
      system_prompt("You are a context-aware assistant.")
    end

    context do
      put(:tenant, "demo")
      put(:channel, "test")
    end
  end

  defmodule StringModelAgent do
    use Moto.Agent

    agent do
      model("openai:gpt-4.1")
      system_prompt("You are a concise assistant.")
    end
  end

  defmodule TenantPrompt do
    @behaviour Moto.Agent.SystemPrompt

    @impl true
    def resolve_system_prompt(%{context: context}) do
      tenant = Map.get(context, :tenant, Map.get(context, "tenant", "unknown"))
      "You are helping tenant #{tenant}."
    end
  end

  defmodule PromptCallbacks do
    def build(%{context: context}, prefix) do
      tenant = Map.get(context, :tenant, Map.get(context, "tenant", "unknown"))
      {:ok, "#{prefix} #{tenant}."}
    end
  end

  defmodule ModulePromptAgent do
    use Moto.Agent

    agent do
      model(:fast)
      system_prompt(TenantPrompt)
    end
  end

  defmodule MfaPromptAgent do
    use Moto.Agent

    agent do
      model(:fast)
      system_prompt({PromptCallbacks, :build, ["Serve tenant"]})
    end
  end

  defmodule InlineMapModelAgent do
    use Moto.Agent

    agent do
      model(%{provider: :openai, id: "gpt-4.1", base_url: "http://localhost:4000/v1"})
      system_prompt("You are a concise assistant.")
    end
  end

  defmodule StructModelAgent do
    use Moto.Agent

    agent do
      model(%LLMDB.Model{provider: :openai, id: "gpt-4.1"})
      system_prompt("You are a concise assistant.")
    end
  end

  defmodule AddNumbers do
    use Moto.Tool,
      description: "Adds two integers together.",
      schema: Zoi.object(%{a: Zoi.integer(), b: Zoi.integer()})

    @impl true
    def run(%{a: a, b: b}, _context) do
      {:ok, %{sum: a + b}}
    end
  end

  defmodule MultiplyNumbers do
    use Moto.Tool,
      description: "Multiplies two integers together.",
      schema: Zoi.object(%{a: Zoi.integer(), b: Zoi.integer()})

    @impl true
    def run(%{a: a, b: b}, _context) do
      {:ok, %{product: a * b}}
    end
  end

  defmodule ToolAgent do
    use Moto.Agent

    agent do
      model(:fast)
      system_prompt("You can use math tools.")
    end

    tools do
      tool(AddNumbers)
    end
  end

  defmodule MathPlugin do
    use Moto.Plugin,
      description: "Provides math tools for Moto agents.",
      tools: [MultiplyNumbers]
  end

  defmodule PluginAgent do
    use Moto.Agent

    agent do
      model(:fast)
      system_prompt("You can use plugin-provided tools.")
    end

    plugins do
      plugin(MathPlugin)
    end
  end

  defmodule InjectTenantHook do
    use Moto.Hook, name: "inject_tenant"

    @impl true
    def call(%Moto.Hooks.BeforeTurn{} = input) do
      sequence = Map.get(input.metadata, :sequence, [])

      {:ok,
       %{
         message: "#{input.message} for acme",
         context: %{tenant: "acme"},
         allowed_tools: ["add_numbers"],
         llm_opts: [temperature: 0.1],
         metadata: %{sequence: sequence ++ ["inject_tenant"], touched?: true}
       }}
    end
  end

  defmodule RestrictRefundsHook do
    use Moto.Hook, name: "restrict_refunds"

    @impl true
    def call(%Moto.Hooks.BeforeTurn{} = input) do
      sequence = Map.get(input.metadata, :sequence, [])
      {:ok, %{metadata: %{sequence: sequence ++ ["restrict_refunds"], mode: :refunds}}}
    end
  end

  defmodule NormalizeReplyHook do
    use Moto.Hook, name: "normalize_reply"

    @impl true
    def call(%Moto.Hooks.AfterTurn{outcome: {:ok, result}}) do
      {:ok, {:ok, "normalized:#{result}"}}
    end

    def call(%Moto.Hooks.AfterTurn{outcome: {:error, reason}}) do
      {:ok, {:error, {:normalized_error, reason}}}
    end
  end

  defmodule InterruptBeforeHook do
    use Moto.Hook, name: "approval_gate"

    @impl true
    def call(%Moto.Hooks.BeforeTurn{} = input) do
      notify_pid = Map.get(input.context, :notify_pid, Map.get(input.context, "notify_pid"))

      {:interrupt,
       %{
         kind: :approval,
         message: "Approval required",
         data: %{notify_pid: notify_pid, from: :before_turn}
       }}
    end
  end

  defmodule InterruptAfterHook do
    use Moto.Hook, name: "interrupt_after_turn"

    @impl true
    def call(%Moto.Hooks.AfterTurn{} = input) do
      notify_pid = Map.get(input.context, :notify_pid, Map.get(input.context, "notify_pid"))

      {:interrupt,
       %{
         kind: :review,
         message: "Review required",
         data: %{notify_pid: notify_pid, from: :after_turn}
       }}
    end
  end

  defmodule NotifyOpsHook do
    use Moto.Hook, name: "notify_ops"

    @impl true
    def call(%Moto.Hooks.InterruptInput{interrupt: interrupt}) do
      if pid = get_in(interrupt.data, [:notify_pid]) do
        send(pid, {:hook_interrupt, interrupt.kind, interrupt.data[:from]})
      end

      :ok
    end
  end

  defmodule HookCallbacks do
    def before_turn(%Moto.Hooks.BeforeTurn{} = input, label) do
      sequence = Map.get(input.metadata, :sequence, [])
      {:ok, %{metadata: %{sequence: sequence ++ [label]}}}
    end

    def after_turn(%Moto.Hooks.AfterTurn{outcome: {:ok, result}}, suffix) do
      {:ok, {:ok, "#{result}#{suffix}"}}
    end

    def after_turn(%Moto.Hooks.AfterTurn{outcome: {:error, reason}}, suffix) do
      {:ok, {:error, {suffix, reason}}}
    end

    def notify_interrupt(%Moto.Hooks.InterruptInput{interrupt: interrupt}, label) do
      if pid = get_in(interrupt.data, [:notify_pid]) do
        send(pid, {:hook_interrupt_callback, label, interrupt.kind})
      end

      :ok
    end
  end

  defmodule SafePromptGuardrail do
    use Moto.Guardrail, name: "safe_prompt"

    @impl true
    def call(%Moto.Guardrails.Input{message: message}) do
      if String.contains?(String.downcase(message), "secret") do
        {:error, :unsafe_prompt}
      else
        :ok
      end
    end
  end

  defmodule SafeReplyGuardrail do
    use Moto.Guardrail, name: "safe_reply"

    @impl true
    def call(%Moto.Guardrails.Output{outcome: {:ok, result}}) when is_binary(result) do
      if String.contains?(String.downcase(result), "unsafe") do
        {:error, :unsafe_reply}
      else
        :ok
      end
    end

    def call(%Moto.Guardrails.Output{}), do: :ok
  end

  defmodule ApproveLargeMathToolGuardrail do
    use Moto.Guardrail, name: "approve_large_math_tool"

    @impl true
    def call(%Moto.Guardrails.Tool{
          tool_name: "add_numbers",
          arguments: arguments,
          context: context
        }) do
      a = Map.get(arguments, :a, Map.get(arguments, "a", 0))
      b = Map.get(arguments, :b, Map.get(arguments, "b", 0))

      if a + b > 40 do
        notify_pid = Map.get(context, :notify_pid, Map.get(context, "notify_pid"))

        {:interrupt,
         %{
           kind: :approval,
           message: "Large calculations require approval",
           data: %{notify_pid: notify_pid, from: :tool_guardrail}
         }}
      else
        :ok
      end
    end

    def call(%Moto.Guardrails.Tool{}), do: :ok
  end

  defmodule GuardrailCallbacks do
    def input(%Moto.Guardrails.Input{} = input, label) do
      sequence = Map.get(input.metadata, :sequence, [])

      if String.contains?(input.message, "blocked_by_#{label}") do
        {:error, {:blocked, label}}
      else
        {:error, {:input_callback, sequence ++ [label]}}
      end
    end

    def output(%Moto.Guardrails.Output{}, label), do: {:error, {:output_callback, label}}

    def tool(%Moto.Guardrails.Tool{}, label), do: {:error, {:tool_callback, label}}
  end

  defmodule HookedAgent do
    use Moto.Agent

    agent do
      model(:fast)
      system_prompt("You have hooks.")
    end

    hooks do
      before_turn(InjectTenantHook)
      before_turn({HookCallbacks, :before_turn, ["dsl_mfa"]})
      after_turn(NormalizeReplyHook)
      after_turn({HookCallbacks, :after_turn, ["!"]})
      on_interrupt(NotifyOpsHook)
      on_interrupt({HookCallbacks, :notify_interrupt, ["dsl_mfa"]})
    end
  end

  defmodule GuardrailedAgent do
    use Moto.Agent

    agent do
      model(:fast)
      system_prompt("You enforce guardrails.")
    end

    tools do
      tool(AddNumbers)
    end

    hooks do
      on_interrupt(NotifyOpsHook)
    end

    guardrails do
      input(SafePromptGuardrail)
      output(SafeReplyGuardrail)
      tool(ApproveLargeMathToolGuardrail)
    end
  end

  defmodule MemoryAgent do
    use Moto.Agent

    agent do
      model(:fast)
      system_prompt("You have conversation memory.")
    end

    memory do
      mode(:conversation)
      namespace({:context, :session})
      capture(:conversation)
      retrieve(limit: 4)
      inject(:system_prompt)
    end
  end

  defmodule ContextMemoryAgent do
    use Moto.Agent

    agent do
      model(:fast)
      system_prompt("You have context memory.")
    end

    memory do
      mode(:conversation)
      namespace({:context, :session})
      capture(:conversation)
      retrieve(limit: 4)
      inject(:context)
    end
  end

  defmodule SharedMemoryAgent do
    use Moto.Agent

    agent do
      model(:fast)
      system_prompt("You have shared memory.")
    end

    memory do
      mode(:conversation)
      namespace(:shared)
      shared_namespace("shared-demo")
      capture(:conversation)
      retrieve(limit: 4)
      inject(:context)
    end
  end

  defmodule NoCaptureMemoryAgent do
    use Moto.Agent

    agent do
      model(:fast)
      system_prompt("You have retrieval only memory.")
    end

    memory do
      mode(:conversation)
      namespace({:context, :session})
      capture(:off)
      retrieve(limit: 4)
      inject(:context)
    end
  end

  defmodule InterruptingAgent do
    use Moto.Agent

    agent do
      model(:fast)
      system_prompt("You may interrupt.")
    end

    hooks do
      before_turn(InterruptBeforeHook)
      on_interrupt(NotifyOpsHook)
    end
  end

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

  test "wraps Jido.Action with Moto.Tool defaults" do
    assert AddNumbers.name() == "add_numbers"
    assert AddNumbers.description() == "Adds two integers together."
    assert %{name: "add_numbers", parameters_schema: %{}} = AddNumbers.to_tool()
  end

  test "exposes configured tool modules and names" do
    assert ToolAgent.tools() == [AddNumbers]
    assert ToolAgent.tool_names() == ["add_numbers"]
  end

  test "wraps Jido.Plugin with Moto.Plugin defaults" do
    assert MathPlugin.name() == "math_plugin"
    assert MathPlugin.state_key() == :math_plugin
    assert MathPlugin.actions() == [MultiplyNumbers]
  end

  test "wraps Moto.Hook with published names" do
    assert Moto.Hook.validate_hook_module(InjectTenantHook) == :ok
    assert {:ok, "inject_tenant"} = Moto.Hook.hook_name(InjectTenantHook)

    assert {:ok, ["inject_tenant", "normalize_reply"]} =
             Moto.Hook.hook_names([InjectTenantHook, NormalizeReplyHook])
  end

  test "wraps Moto.Guardrail with published names" do
    assert Moto.Guardrail.validate_guardrail_module(SafePromptGuardrail) == :ok
    assert {:ok, "safe_prompt"} = Moto.Guardrail.guardrail_name(SafePromptGuardrail)

    assert {:ok, ["safe_prompt", "safe_reply"]} =
             Moto.Guardrail.guardrail_names([SafePromptGuardrail, SafeReplyGuardrail])
  end

  test "exposes configured plugin modules and names" do
    assert PluginAgent.plugins() == [MathPlugin]
    assert PluginAgent.plugin_names() == ["math_plugin"]
  end

  test "merges plugin actions into the agent tool registry" do
    assert PluginAgent.tools() == [MultiplyNumbers]
    assert PluginAgent.tool_names() == ["multiply_numbers"]
  end

  test "exposes configured hooks by stage" do
    assert HookedAgent.hooks() == %{
             before_turn: [InjectTenantHook, {HookCallbacks, :before_turn, ["dsl_mfa"]}],
             after_turn: [NormalizeReplyHook, {HookCallbacks, :after_turn, ["!"]}],
             on_interrupt: [NotifyOpsHook, {HookCallbacks, :notify_interrupt, ["dsl_mfa"]}]
           }

    assert HookedAgent.before_turn_hooks() ==
             [InjectTenantHook, {HookCallbacks, :before_turn, ["dsl_mfa"]}]

    assert HookedAgent.after_turn_hooks() ==
             [NormalizeReplyHook, {HookCallbacks, :after_turn, ["!"]}]

    assert HookedAgent.interrupt_hooks() ==
             [NotifyOpsHook, {HookCallbacks, :notify_interrupt, ["dsl_mfa"]}]
  end

  test "exposes configured guardrails by stage" do
    assert GuardrailedAgent.guardrails() == %{
             input: [SafePromptGuardrail],
             output: [SafeReplyGuardrail],
             tool: [ApproveLargeMathToolGuardrail]
           }

    assert GuardrailedAgent.input_guardrails() == [SafePromptGuardrail]
    assert GuardrailedAgent.output_guardrails() == [SafeReplyGuardrail]
    assert GuardrailedAgent.tool_guardrails() == [ApproveLargeMathToolGuardrail]
  end

  test "accepts request-scoped module, MFA, and function hooks" do
    runtime_fun = fn %Moto.Hooks.BeforeTurn{} = input ->
      sequence = Map.get(input.metadata, :sequence, [])
      {:ok, %{metadata: %{sequence: sequence ++ ["runtime_fn"]}}}
    end

    assert {:ok, opts} =
             Moto.Agent.prepare_chat_opts(
               [
                 context: %{tenant: "runtime"},
                 hooks: [
                   before_turn: [
                     InjectTenantHook,
                     {HookCallbacks, :before_turn, ["runtime_mfa"]},
                     runtime_fun
                   ]
                 ]
               ],
               nil
             )

    tool_context = Keyword.fetch!(opts, :tool_context)

    assert %{
             before_turn: [
               InjectTenantHook,
               {HookCallbacks, :before_turn, ["runtime_mfa"]},
               ^runtime_fun
             ]
           } =
             tool_context[:__moto_hooks__]
  end

  test "accepts request-scoped module, MFA, and function guardrails" do
    runtime_fun = fn %Moto.Guardrails.Input{} = input ->
      {:error, {:runtime_input, input.message}}
    end

    assert {:ok, opts} =
             Moto.Agent.prepare_chat_opts(
               [
                 context: %{tenant: "runtime"},
                 guardrails: [
                   input: [
                     SafePromptGuardrail,
                     {GuardrailCallbacks, :input, ["runtime_mfa"]},
                     runtime_fun
                   ]
                 ]
               ],
               nil
             )

    tool_context = Keyword.fetch!(opts, :tool_context)

    assert %{
             input: [
               SafePromptGuardrail,
               {GuardrailCallbacks, :input, ["runtime_mfa"]},
               ^runtime_fun
             ]
           } =
             tool_context[:__moto_guardrails__]
  end

  test "accepts context keyword lists and normalizes them to internal tool_context" do
    assert {:ok, opts} =
             Moto.Agent.prepare_chat_opts([context: [tenant: "acme", locale: "en-US"]], nil)

    assert Keyword.get(opts, :tool_context) == %{tenant: "acme", locale: "en-US"}
  end

  test "merges default agent context with per-turn context" do
    assert {:ok, opts} =
             Moto.Agent.prepare_chat_opts(
               [context: %{session: "runtime"}],
               %{context: ContextAgent.context()}
             )

    assert Keyword.get(opts, :tool_context) == %{
             tenant: "demo",
             channel: "test",
             session: "runtime"
           }
  end

  test "merges default agent context into runtime requests" do
    runtime = ContextAgent.runtime_module()
    agent = new_runtime_agent(runtime)

    assert {:ok, _agent, {:ai_react_start, params}} =
             runtime.on_before_cmd(
               agent,
               {:ai_react_start, %{query: "hello", request_id: "req-context-1"}}
             )

    assert params.tool_context == %{tenant: "demo", channel: "test"}
    assert params.runtime_context == %{tenant: "demo", channel: "test"}
  end

  test "retrieves and captures conversation memory across turns" do
    runtime = MemoryAgent.runtime_module()
    agent = new_runtime_agent(runtime)
    session = "memory-session-#{System.unique_integer([:positive])}"

    {:ok, agent, _action} =
      runtime.on_before_cmd(
        agent,
        {:ai_react_start,
         %{
           query: "Remember that my favorite color is blue.",
           request_id: "req-memory-1",
           tool_context: %{session: session}
         }}
      )

    agent =
      Jido.AI.Request.complete_request(
        agent,
        "req-memory-1",
        "I'll remember that your favorite color is blue."
      )

    assert {:ok, agent, []} =
             runtime.on_after_cmd(agent, {:ai_react_start, %{request_id: "req-memory-1"}}, [])

    assert {:ok, agent, {:ai_react_start, params}} =
             runtime.on_before_cmd(
               agent,
               {:ai_react_start,
                %{
                  query: "What is my favorite color?",
                  request_id: "req-memory-2",
                  tool_context: %{session: session}
                }}
             )

    memory = params.tool_context[Moto.Memory.context_key()]
    assert memory.namespace == "agent:memory_agent:context:session:#{session}"
    assert Enum.map(memory.records, & &1.kind) == [:user_turn, :assistant_turn]
    assert params.runtime_context == params.tool_context

    assert memory.prompt =~ "Relevant memory:"
    assert memory.prompt =~ "favorite color is blue"

    assert get_in(agent.state, [:requests, "req-memory-2", :meta, :moto_memory, :namespace]) ==
             "agent:memory_agent:context:session:#{session}"
  end

  test "inject :context exposes retrieved memory on the runtime context" do
    runtime = ContextMemoryAgent.runtime_module()
    agent = new_runtime_agent(runtime)
    session = "context-memory-#{System.unique_integer([:positive])}"

    {:ok, agent, _action} =
      runtime.on_before_cmd(
        agent,
        {:ai_react_start,
         %{
           query: "Remember that I prefer green tea.",
           request_id: "req-memory-ctx-1",
           tool_context: %{session: session}
         }}
      )

    agent = Jido.AI.Request.complete_request(agent, "req-memory-ctx-1", "I'll remember that.")

    assert {:ok, agent, []} =
             runtime.on_after_cmd(agent, {:ai_react_start, %{request_id: "req-memory-ctx-1"}}, [])

    assert {:ok, _agent, {:ai_react_start, params}} =
             runtime.on_before_cmd(
               agent,
               {:ai_react_start,
                %{
                  query: "What drink do I prefer?",
                  request_id: "req-memory-ctx-2",
                  tool_context: %{session: session}
                }}
             )

    assert ContextMemoryAgent.request_transformer() == nil
    assert %{namespace: _, records: [_user, _assistant]} = params.tool_context[:memory]
  end

  test "shared memory namespaces are visible across agent instances" do
    runtime = SharedMemoryAgent.runtime_module()
    first_agent = new_runtime_agent(runtime)
    second_agent = new_runtime_agent(runtime)

    {:ok, first_agent, _action} =
      runtime.on_before_cmd(
        first_agent,
        {:ai_react_start,
         %{query: "Remember that the shared color is red.", request_id: "req-memory-shared-1"}}
      )

    first_agent = Jido.AI.Request.complete_request(first_agent, "req-memory-shared-1", "Stored.")

    assert {:ok, _first_agent, []} =
             runtime.on_after_cmd(
               first_agent,
               {:ai_react_start, %{request_id: "req-memory-shared-1"}},
               []
             )

    assert {:ok, _second_agent, {:ai_react_start, params}} =
             runtime.on_before_cmd(
               second_agent,
               {:ai_react_start,
                %{query: "What is the shared color?", request_id: "req-memory-shared-2"}}
             )

    assert params.tool_context[:memory].namespace == "shared:shared-demo"

    assert Enum.any?(params.tool_context[:memory].records, fn record ->
             to_string(record.kind) == "user_turn" and
               String.contains?(record.text || "", "shared color is red")
           end)
  end

  test "capture :off skips conversation writes" do
    runtime = NoCaptureMemoryAgent.runtime_module()
    agent = new_runtime_agent(runtime)
    session = "memory-off-#{System.unique_integer([:positive])}"

    {:ok, agent, _action} =
      runtime.on_before_cmd(
        agent,
        {:ai_react_start,
         %{
           query: "Remember that I like coffee.",
           request_id: "req-memory-off-1",
           tool_context: %{session: session}
         }}
      )

    agent = Jido.AI.Request.complete_request(agent, "req-memory-off-1", "I will not store this.")

    assert {:ok, agent, []} =
             runtime.on_after_cmd(agent, {:ai_react_start, %{request_id: "req-memory-off-1"}}, [])

    assert {:ok, _agent, {:ai_react_start, params}} =
             runtime.on_before_cmd(
               agent,
               {:ai_react_start,
                %{
                  query: "What drink do I like?",
                  request_id: "req-memory-off-2",
                  tool_context: %{session: session}
                }}
             )

    assert params.tool_context[:memory].records == []
  end

  test "runs before_turn hooks in declaration order and rewrites request params" do
    runtime = HookedAgent.runtime_module()
    agent = new_runtime_agent(runtime)

    assert {:ok, updated_agent, {:ai_react_start, params}} =
             runtime.on_before_cmd(
               agent,
               {:ai_react_start,
                %{query: "hello", request_id: "req-hook-1", tool_context: %{notify_pid: self()}}}
             )

    assert params.query == "hello for acme"
    assert params.tool_context == %{notify_pid: self(), tenant: "acme"}
    assert params.allowed_tools == ["add_numbers"]
    assert params.llm_opts == [temperature: 0.1]

    assert get_in(updated_agent.state, [
             :requests,
             "req-hook-1",
             :meta,
             :moto_hooks,
             :metadata,
             :sequence
           ]) ==
             ["inject_tenant", "dsl_mfa"]
  end

  test "runs after_turn hooks in reverse order for successful outcomes" do
    runtime = HookedAgent.runtime_module()
    agent = new_runtime_agent(runtime)

    {:ok, agent, _action} =
      runtime.on_before_cmd(
        agent,
        {:ai_react_start,
         %{query: "hello", request_id: "req-hook-2", tool_context: %{notify_pid: self()}}}
      )

    agent = Jido.AI.Request.complete_request(agent, "req-hook-2", "done")

    assert {:ok, updated_agent, []} =
             runtime.on_after_cmd(agent, {:ai_react_start, %{request_id: "req-hook-2"}}, [])

    assert Jido.AI.Request.get_result(updated_agent, "req-hook-2") == {:ok, "normalized:done!"}
  end

  test "runs after_turn hooks in reverse order for failed outcomes" do
    runtime = HookedAgent.runtime_module()
    agent = new_runtime_agent(runtime)

    {:ok, agent, _action} =
      runtime.on_before_cmd(
        agent,
        {:ai_react_start,
         %{query: "hello", request_id: "req-hook-3", tool_context: %{notify_pid: self()}}}
      )

    agent = Jido.AI.Request.fail_request(agent, "req-hook-3", :boom)

    assert {:ok, updated_agent, []} =
             runtime.on_after_cmd(agent, {:ai_react_start, %{request_id: "req-hook-3"}}, [])

    assert Jido.AI.Request.get_result(updated_agent, "req-hook-3") ==
             {:error, {:normalized_error, {"!", :boom}}}
  end

  test "stores hook metadata per request" do
    runtime = HookedAgent.runtime_module()
    agent = new_runtime_agent(runtime)

    {:ok, agent, _action} =
      runtime.on_before_cmd(
        agent,
        {:ai_react_start,
         %{query: "first", request_id: "req-hook-4", tool_context: %{notify_pid: self()}}}
      )

    {:ok, agent, _action} =
      runtime.on_before_cmd(
        agent,
        {:ai_react_start,
         %{query: "second", request_id: "req-hook-5", tool_context: %{notify_pid: self()}}}
      )

    assert get_in(agent.state, [:requests, "req-hook-4", :meta, :moto_hooks, :message]) ==
             "first for acme"

    assert get_in(agent.state, [:requests, "req-hook-5", :meta, :moto_hooks, :message]) ==
             "second for acme"
  end

  test "translates default hook interrupts from MyAgent.chat and runs interrupt hooks" do
    assert {:ok, pid} = InterruptingAgent.start_link(id: "interrupting-agent-test")

    try do
      assert {:interrupt, %Moto.Interrupt{kind: :approval, message: "Approval required"}} =
               InterruptingAgent.chat(pid, "Refund this order", context: [notify_pid: self()])

      assert_receive {:hook_interrupt, :approval, :before_turn}
    after
      :ok = Moto.stop_agent(pid)
    end
  end

  test "translates failed interrupt envelopes from tool guardrails" do
    interrupt = Moto.Interrupt.new(kind: :approval, message: "Need approval")

    assert Moto.Hooks.translate_chat_result({:error, {:failed, :error, {:interrupt, interrupt}}}) ==
             {:interrupt, interrupt}
  end

  test "translates request-scoped interrupt hooks from Moto.chat and supports runtime functions" do
    assert {:ok, pid} = ChatAgent.start_link(id: "runtime-hook-agent-test")
    test_pid = self()

    before_turn = fn _input ->
      {:interrupt,
       %{
         kind: :manual_review,
         message: "Manual review required",
         data: %{notify_pid: test_pid, from: :runtime}
       }}
    end

    on_interrupt = fn %Moto.Hooks.InterruptInput{interrupt: interrupt} ->
      send(test_pid, {:runtime_interrupt, interrupt.kind})
      :ok
    end

    try do
      assert {:interrupt, %Moto.Interrupt{kind: :manual_review}} =
               Moto.chat(pid, "Check this request",
                 context: [notify_pid: self()],
                 hooks: [before_turn: before_turn, on_interrupt: on_interrupt]
               )

      assert_receive {:runtime_interrupt, :manual_review}
    after
      :ok = Moto.stop_agent(pid)
    end
  end

  test "runs input guardrails and blocks before the LLM call" do
    runtime = GuardrailedAgent.runtime_module()
    agent = new_runtime_agent(runtime)

    assert {:ok, updated_agent,
            {:ai_react_request_error,
             %{request_id: "req-guard-1", reason: :guardrail_blocked, message: "Tell me the secret"}}} =
             runtime.on_before_cmd(
               agent,
               {:ai_react_start, %{query: "Tell me the secret", request_id: "req-guard-1"}}
             )

    assert Jido.AI.Request.get_result(updated_agent, "req-guard-1") ==
             {:error, {:guardrail, :input, "safe_prompt", :unsafe_prompt}}
  end

  test "runs output guardrails after hooks and blocks the final result" do
    runtime = GuardrailedAgent.runtime_module()
    agent = new_runtime_agent(runtime)

    {:ok, agent, _action} =
      runtime.on_before_cmd(
        agent,
        {:ai_react_start, %{query: "hello", request_id: "req-guard-2"}}
      )

    agent = Jido.AI.Request.complete_request(agent, "req-guard-2", "unsafe output")

    assert {:ok, updated_agent, []} =
             runtime.on_after_cmd(agent, {:ai_react_start, %{request_id: "req-guard-2"}}, [])

    assert Jido.AI.Request.get_result(updated_agent, "req-guard-2") ==
             {:error, {:guardrail, :output, "safe_reply", :unsafe_reply}}
  end

  test "tool guardrails attach a runtime callback that interrupts before tool execution" do
    runtime = GuardrailedAgent.runtime_module()
    agent = new_runtime_agent(runtime)
    test_pid = self()

    assert {:ok, _agent, {:ai_react_start, params}} =
             runtime.on_before_cmd(
               agent,
               {:ai_react_start,
                %{
                  query: "calculate",
                  request_id: "req-guard-callback",
                  tool_context: %{notify_pid: test_pid}
                }}
             )

    tool_context = Map.fetch!(params, :tool_context)
    callback = Map.fetch!(tool_context, :__tool_guardrail_callback__)

    assert {:interrupt,
            %Moto.Interrupt{kind: :approval, message: "Large calculations require approval"}} =
             callback.(%{
               tool_name: "add_numbers",
               tool_call_id: "tc-large",
               arguments: %{a: 70, b: 50},
               context: tool_context
             })

    assert_receive {:hook_interrupt, :approval, :tool_guardrail}
  end

  test "translates input guardrail interrupts from Moto.chat and runs interrupt hooks" do
    assert {:ok, pid} = GuardrailedAgent.start_link(id: "guardrailed-agent-test")
    test_pid = self()

    try do
      assert {:interrupt, %Moto.Interrupt{kind: :approval}} =
               Moto.chat(pid, "hello",
                 context: %{notify_pid: test_pid},
                 guardrails: [
                   input: fn _input ->
                     {:interrupt,
                      %{
                        kind: :approval,
                        message: "Need approval",
                        data: %{notify_pid: test_pid}
                      }}
                   end
                 ]
               )

      assert_receive {:hook_interrupt, :approval, nil}
    after
      :ok = Moto.stop_agent(pid)
    end
  end

  test "handles ai.tool.started without routing errors in generated runtimes" do
    assert {:ok, pid} = ChatAgent.start_link(id: "tool-started-route-test")

    try do
      log =
        capture_log(fn ->
          :ok =
            Jido.AgentServer.cast(
              pid,
              Jido.AI.Signal.ToolStarted.new!(%{
                call_id: "call-test",
                tool_name: "add_numbers"
              })
            )

          Process.sleep(50)
        end)

      refute log =~ "No route for signal"
    after
      :ok = Moto.stop_agent(pid)
    end
  end

  test "expands ash_resource into generated AshJido action modules" do
    assert AshResourceAgent.ash_resources() == [User]
    assert AshResourceAgent.ash_domain() == Accounts
    assert AshResourceAgent.requires_actor?()
    assert Enum.sort(AshResourceAgent.tool_names()) == ["create_user", "list_users"]

    assert Enum.any?(AshResourceAgent.tools(), &(&1 == MotoTest.Support.User.Jido.Create))
    assert Enum.any?(AshResourceAgent.tools(), &(&1 == MotoTest.Support.User.Jido.Read))
  end

  test "rejects old keyword opts in favor of the DSL" do
    assert_raise CompileError, ~r/Moto.Agent now uses a Spark DSL/, fn ->
      Code.compile_string("""
      defmodule MotoTest.InvalidKeywordAgent do
        use Moto.Agent,
          system_prompt: "This should fail."
      end
      """)
    end
  end

  test "rejects invalid model configuration at compile time" do
    assert_raise Spark.Error.DslError, ~r/invalid model input 123/, fn ->
      Code.compile_string("""
      defmodule MotoTest.InvalidModelAgent do
        use Moto.Agent

        agent do
          model 123
          system_prompt "This should fail."
        end
      end
      """)
    end
  end

  test "rejects anonymous functions as system prompts at compile time" do
    assert_raise Spark.Error.DslError, ~r/does not support anonymous functions/, fn ->
      Code.compile_string("""
      defmodule MotoTest.InvalidDynamicPromptAgent do
        use Moto.Agent

        agent do
          system_prompt fn _input -> "This should fail." end
        end
      end
      """)
    end
  end

  test "rejects anonymous functions in DSL hooks at compile time" do
    assert_raise Spark.Error.DslError, ~r/DSL hooks do not support anonymous functions/, fn ->
      Code.compile_string("""
      defmodule MotoTest.InvalidHookFnAgent do
        use Moto.Agent

        agent do
          system_prompt "This should fail."
        end

        hooks do
          before_turn fn _input -> {:ok, %{}} end
        end
      end
      """)
    end
  end

  test "rejects anonymous functions in DSL guardrails at compile time" do
    assert_raise Spark.Error.DslError,
                 ~r/DSL guardrails do not support anonymous functions/,
                 fn ->
                   Code.compile_string("""
                   defmodule MotoTest.InvalidGuardrailFnAgent do
                     use Moto.Agent

                     agent do
                       system_prompt "This should fail."
                     end

                     guardrails do
                       input fn _input -> :ok end
                     end
                   end
                   """)
                 end
  end

  test "rejects invalid memory modes at compile time" do
    assert_raise Spark.Error.DslError, ~r/memory mode must be :conversation/, fn ->
      Code.compile_string("""
      defmodule MotoTest.InvalidMemoryModeAgent do
        use Moto.Agent

        agent do
          system_prompt "This should fail."
        end

        memory do
          mode :semantic
        end
      end
      """)
    end
  end

  test "rejects invalid memory namespaces at compile time" do
    assert_raise Spark.Error.DslError, ~r/memory namespace must be/, fn ->
      Code.compile_string("""
      defmodule MotoTest.InvalidMemoryNamespaceAgent do
        use Moto.Agent

        agent do
          system_prompt "This should fail."
        end

        memory do
          namespace :shared
        end
      end
      """)
    end
  end

  test "rejects invalid hook modules at compile time" do
    assert_raise Spark.Error.DslError, ~r/not a valid Moto hook/, fn ->
      Code.compile_string("""
      defmodule MotoTest.InvalidHookAgent do
        use Moto.Agent

        agent do
          system_prompt "This should fail."
        end

        hooks do
          before_turn String
        end
      end
      """)
    end
  end

  test "rejects invalid guardrail modules at compile time" do
    assert_raise Spark.Error.DslError, ~r/not a valid Moto guardrail/, fn ->
      Code.compile_string("""
      defmodule MotoTest.InvalidGuardrailAgent do
        use Moto.Agent

        agent do
          system_prompt "This should fail."
        end

        guardrails do
          input String
        end
      end
      """)
    end
  end

  test "rejects invalid tool modules at compile time" do
    assert_raise Spark.Error.DslError, ~r/not a valid Moto tool/, fn ->
      Code.compile_string("""
      defmodule MotoTest.InvalidToolAgent do
        use Moto.Agent

        agent do
          system_prompt "This should fail."
        end

        tools do
          tool String
        end
      end
      """)
    end
  end

  test "rejects invalid ash_resource modules at compile time" do
    assert_raise Spark.Error.DslError, ~r/not an Ash resource/, fn ->
      Code.compile_string("""
      defmodule MotoTest.InvalidAshResourceAgent do
        use Moto.Agent

        agent do
          system_prompt "This should fail."
        end

        tools do
          ash_resource String
        end
      end
      """)
    end
  end

  test "rejects invalid plugin modules at compile time" do
    assert_raise Spark.Error.DslError, ~r/not a valid Moto plugin/, fn ->
      Code.compile_string("""
      defmodule MotoTest.InvalidPluginAgent do
        use Moto.Agent

        agent do
          system_prompt "This should fail."
        end

        plugins do
          plugin String
        end
      end
      """)
    end
  end

  test "rejects NimbleOptions schemas in Moto.Tool" do
    assert_raise CompileError, ~r/must use a Zoi schema for schema\/0/, fn ->
      Code.compile_string("""
      defmodule MotoTest.NimbleSchemaTool do
        use Moto.Tool,
          schema: [a: [type: :integer, required: true]]

        @impl true
        def run(params, _context), do: {:ok, params}
      end
      """)
    end
  end

  test "rejects raw JSON Schema maps in Moto.Tool" do
    assert_raise CompileError, ~r/must use a Zoi schema for schema\/0/, fn ->
      Code.compile_string("""
      defmodule MotoTest.JsonSchemaTool do
        use Moto.Tool,
          schema: %{"type" => "object", "properties" => %{"a" => %{"type" => "integer"}}}

        @impl true
        def run(params, _context), do: {:ok, params}
      end
      """)
    end
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

  test "rejects public tool_context in favor of context" do
    assert {:error, {:invalid_option, :tool_context, :use_context}} =
             Moto.Agent.prepare_chat_opts([tool_context: %{actor: %{id: "user-1"}}], nil)
  end

  test "rejects public tool_context in chat helpers" do
    assert {:ok, pid} = ChatAgent.start_link(id: "invalid-tool-context-chat-test")

    try do
      assert {:error, {:invalid_option, :tool_context, :use_context}} =
               ChatAgent.chat(pid, "Hello", tool_context: %{tenant: "acme"})

      assert {:error, {:invalid_option, :tool_context, :use_context}} =
               Moto.chat(pid, "Hello", tool_context: %{tenant: "acme"})
    after
      :ok = Moto.stop_agent(pid)
    end
  end

  test "imports a constrained dynamic agent from JSON" do
    json = """
    {
      "name": "json_agent",
      "model": "fast",
      "system_prompt": "You are a concise assistant.",
      "context": {"tenant": "json", "channel": "imported"},
      "tools": ["add_numbers"],
      "plugins": ["math_plugin"],
      "hooks": {
        "before_turn": ["inject_tenant", "restrict_refunds"],
        "after_turn": ["normalize_reply"],
        "on_interrupt": ["notify_ops"]
      },
      "guardrails": {
        "input": ["safe_prompt"],
        "output": ["safe_reply"],
        "tool": ["approve_large_math_tool"]
      }
    }
    """

    assert {:ok, %DynamicAgent{} = agent} =
             Moto.import_agent(
               json,
               available_tools: [AddNumbers],
               available_plugins: [MathPlugin],
               available_hooks: [
                 InjectTenantHook,
                 RestrictRefundsHook,
                 NormalizeReplyHook,
                 NotifyOpsHook
               ],
               available_guardrails: [
                 SafePromptGuardrail,
                 SafeReplyGuardrail,
                 ApproveLargeMathToolGuardrail
               ]
             )

    assert {:ok, encoded} = Moto.encode_agent(agent, format: :json)
    assert encoded =~ "\"name\": \"json_agent\""
    assert encoded =~ "\"model\": \"fast\""
    assert encoded =~ "\"context\": {"
    assert encoded =~ "\"tools\": ["
    assert encoded =~ "\"plugins\": ["
    assert encoded =~ "\"hooks\""
    assert encoded =~ "\"guardrails\""
    assert agent.spec.context == %{"tenant" => "json", "channel" => "imported"}
    assert agent.tool_modules == [AddNumbers, MultiplyNumbers]
    assert agent.plugin_modules == [MathPlugin]
    assert agent.hook_modules.before_turn == [InjectTenantHook, RestrictRefundsHook]
    assert agent.hook_modules.after_turn == [NormalizeReplyHook]
    assert agent.hook_modules.on_interrupt == [NotifyOpsHook]
    assert agent.guardrail_modules.input == [SafePromptGuardrail]
    assert agent.guardrail_modules.output == [SafeReplyGuardrail]
    assert agent.guardrail_modules.tool == [ApproveLargeMathToolGuardrail]
  end

  test "imports a constrained dynamic agent from YAML" do
    yaml = """
    name: "yaml_agent"
    model:
      provider: "openai"
      id: "gpt-4.1"
    system_prompt: |-
      You are a concise assistant.
    context:
      tenant: "yaml"
      channel: "imported"
    tools:
      - "add_numbers"
    plugins:
      - "math_plugin"
    hooks:
      before_turn:
        - "inject_tenant"
        - "restrict_refunds"
      after_turn:
        - "normalize_reply"
      on_interrupt:
        - "notify_ops"
    guardrails:
      input:
        - "safe_prompt"
      output:
        - "safe_reply"
      tool:
        - "approve_large_math_tool"
    """

    assert {:ok, %DynamicAgent{} = agent} =
             Moto.import_agent(
               yaml,
               format: :yaml,
               available_tools: [AddNumbers],
               available_plugins: [MathPlugin],
               available_hooks: [
                 InjectTenantHook,
                 RestrictRefundsHook,
                 NormalizeReplyHook,
                 NotifyOpsHook
               ],
               available_guardrails: [
                 SafePromptGuardrail,
                 SafeReplyGuardrail,
                 ApproveLargeMathToolGuardrail
               ]
             )

    assert {:ok, encoded} = Moto.encode_agent(agent, format: :yaml)
    assert encoded =~ "name: \"yaml_agent\""
    assert encoded =~ "provider: \"openai\""
    assert encoded =~ "context:"
    assert encoded =~ "tenant: \"yaml\""
    assert encoded =~ "- \"add_numbers\""
    assert encoded =~ "- \"math_plugin\""
    assert encoded =~ "hooks:"
    assert encoded =~ "- \"notify_ops\""
    assert encoded =~ "guardrails:"
    assert agent.tool_modules == [AddNumbers, MultiplyNumbers]
    assert agent.spec.context == %{"tenant" => "yaml", "channel" => "imported"}
    assert agent.hook_modules.before_turn == [InjectTenantHook, RestrictRefundsHook]
    assert agent.guardrail_modules.tool == [ApproveLargeMathToolGuardrail]
  end

  test "imports a constrained dynamic agent from file" do
    path = Path.join(System.tmp_dir!(), "moto-dynamic-agent.json")

    on_exit(fn -> File.rm(path) end)

    File.write!(
      path,
      ~s({"name":"file_agent","model":"fast","system_prompt":"You are concise.","context":{"tenant":"file","channel":"imported"},"tools":["add_numbers"],"plugins":["math_plugin"],"hooks":{"before_turn":["inject_tenant"],"after_turn":["normalize_reply"],"on_interrupt":["notify_ops"]},"guardrails":{"input":["safe_prompt"],"output":["safe_reply"],"tool":["approve_large_math_tool"]}})
    )

    assert {:ok, %DynamicAgent{} = agent} =
             Moto.import_agent_file(
               path,
               available_tools: [AddNumbers],
               available_plugins: [MathPlugin],
               available_hooks: [InjectTenantHook, NormalizeReplyHook, NotifyOpsHook],
               available_guardrails: [
                 SafePromptGuardrail,
                 SafeReplyGuardrail,
                 ApproveLargeMathToolGuardrail
               ]
             )

    assert agent.tool_modules == [AddNumbers, MultiplyNumbers]
    assert agent.plugin_modules == [MathPlugin]
    assert agent.spec.context == %{"tenant" => "file", "channel" => "imported"}
    assert agent.hook_modules.before_turn == [InjectTenantHook]
    assert agent.guardrail_modules.input == [SafePromptGuardrail]
  end

  test "starts an imported dynamic agent under the shared runtime" do
    json = """
    {
      "name": "runtime_agent",
      "model": "fast",
      "system_prompt": "You are a concise assistant.",
      "tools": ["add_numbers"],
      "plugins": ["math_plugin"],
      "hooks": {
        "before_turn": ["approval_gate"],
        "on_interrupt": ["notify_ops"]
      }
    }
    """

    assert {:ok, %DynamicAgent{} = agent} =
             Moto.import_agent(
               json,
               available_tools: [AddNumbers],
               available_plugins: [MathPlugin],
               available_hooks: [InterruptBeforeHook, NotifyOpsHook],
               available_guardrails: [SafePromptGuardrail]
             )

    assert {:ok, pid} = Moto.start_agent(agent, id: "dynamic-agent-test")
    assert is_pid(pid)
    assert Moto.whereis("dynamic-agent-test") == pid
    assert :ok = Moto.stop_agent(pid)
  end

  test "merges imported default context into runtime requests" do
    assert {:ok, %DynamicAgent{} = agent} =
             Moto.import_agent(%{
               "name" => "runtime_context_agent",
               "model" => "fast",
               "system_prompt" => "You are concise.",
               "context" => %{"tenant" => "imported", "channel" => "json"}
             })

    runtime = agent.runtime_module
    runtime_agent = new_runtime_agent(runtime)

    assert {:ok, _agent, {:ai_react_start, params}} =
             runtime.on_before_cmd(
               runtime_agent,
               {:ai_react_start,
                %{
                  query: "hello",
                  request_id: "req-imported-context",
                  tool_context: %{session: "runtime"}
                }}
             )

    assert params.tool_context == %{
             "tenant" => "imported",
             "channel" => "json",
             session: "runtime"
           }

    assert params.runtime_context == %{
             "tenant" => "imported",
             "channel" => "json",
             session: "runtime"
           }
  end

  test "imports and round-trips memory settings in constrained dynamic agent specs" do
    json = """
    {
      "name": "memory_json_agent",
      "model": "fast",
      "system_prompt": "You are concise.",
      "memory": {
        "mode": "conversation",
        "namespace": "context",
        "context_namespace_key": "session",
        "capture": "conversation",
        "retrieve": {
          "limit": 4
        },
        "inject": "system_prompt"
      }
    }
    """

    assert {:ok, %DynamicAgent{} = agent} = Moto.import_agent(json)

    assert agent.spec.memory == %{
             mode: :conversation,
             namespace: {:context, "session"},
             capture: :conversation,
             retrieve: %{limit: 4},
             inject: :system_prompt
           }

    assert {:ok, encoded_json} = Moto.encode_agent(agent, format: :json)
    assert encoded_json =~ "\"memory\""
    assert encoded_json =~ "\"context_namespace_key\": \"session\""

    assert {:ok, encoded_yaml} = Moto.encode_agent(agent, format: :yaml)
    assert encoded_yaml =~ "memory:"
    assert encoded_yaml =~ "namespace: \"context\""
    assert encoded_yaml =~ "context_namespace_key: \"session\""
  end

  test "imported dynamic agents retrieve and capture memory across turns" do
    assert {:ok, %DynamicAgent{} = agent} =
             Moto.import_agent(%{
               "name" => "imported_memory_agent",
               "model" => "fast",
               "system_prompt" => "You are concise.",
               "memory" => %{
                 "mode" => "conversation",
                 "namespace" => "context",
                 "context_namespace_key" => "session",
                 "capture" => "conversation",
                 "retrieve" => %{"limit" => 4},
                 "inject" => "context"
               }
             })

    runtime = agent.runtime_module
    runtime_agent = new_runtime_agent(runtime)
    session = "imported-memory-#{System.unique_integer([:positive])}"

    {:ok, runtime_agent, _action} =
      runtime.on_before_cmd(
        runtime_agent,
        {:ai_react_start,
         %{
           query: "Remember that I like tea.",
           request_id: "req-imported-memory-1",
           tool_context: %{session: session}
         }}
      )

    runtime_agent =
      Jido.AI.Request.complete_request(runtime_agent, "req-imported-memory-1", "Stored.")

    assert {:ok, runtime_agent, []} =
             runtime.on_after_cmd(
               runtime_agent,
               {:ai_react_start, %{request_id: "req-imported-memory-1"}},
               []
             )

    assert {:ok, _runtime_agent, {:ai_react_start, params}} =
             runtime.on_before_cmd(
               runtime_agent,
               {:ai_react_start,
                %{
                  query: "What do I like?",
                  request_id: "req-imported-memory-2",
                  tool_context: %{session: session}
                }}
             )

    assert %{namespace: _, records: [_user, _assistant]} = params.tool_context[:memory]
  end

  test "rejects unsupported imported memory config" do
    assert {:error, reason} =
             Moto.import_agent(%{
               "name" => "bad_memory_agent",
               "model" => "fast",
               "system_prompt" => "You are concise.",
               "memory" => %{
                 "mode" => "semantic"
               }
             })

    assert reason =~ "memory mode must be :conversation"
  end

  test "rejects unexpected keys in imported dynamic agent specs" do
    assert {:error, reason} =
             Moto.import_agent(%{
               "name" => "bad_agent",
               "model" => "fast",
               "system_prompt" => "You are concise.",
               "extra" => true
             })

    assert reason =~ "unrecognized"
  end

  test "rejects unknown bare model aliases in imported dynamic agent specs" do
    assert {:error, reason} =
             Moto.import_agent(%{
               "name" => "bad_model_agent",
               "model" => "does_not_exist",
               "system_prompt" => "You are concise."
             })

    assert reason =~ "known alias string"
  end

  test "rejects unknown tool names in imported dynamic agent specs" do
    assert {:error, reason} =
             Moto.import_agent(
               %{
                 "name" => "bad_tool_agent",
                 "model" => "fast",
                 "system_prompt" => "You are concise.",
                 "tools" => ["does_not_exist"]
               },
               available_tools: [AddNumbers]
             )

    assert reason =~ "unknown tool"
  end

  test "rejects duplicate tool names in imported dynamic agent specs" do
    assert {:error, reason} =
             Moto.import_agent(
               %{
                 "name" => "duplicate_tool_agent",
                 "model" => "fast",
                 "system_prompt" => "You are concise.",
                 "tools" => ["add_numbers", "add_numbers"]
               },
               available_tools: [AddNumbers]
             )

    assert reason =~ "tools must be unique"
  end

  test "rejects unknown plugin names in imported dynamic agent specs" do
    assert {:error, reason} =
             Moto.import_agent(
               %{
                 "name" => "bad_plugin_agent",
                 "model" => "fast",
                 "system_prompt" => "You are concise.",
                 "plugins" => ["does_not_exist"]
               },
               available_plugins: [MathPlugin]
             )

    assert reason =~ "unknown plugin"
  end

  test "rejects duplicate plugin names in imported dynamic agent specs" do
    assert {:error, reason} =
             Moto.import_agent(
               %{
                 "name" => "duplicate_plugin_agent",
                 "model" => "fast",
                 "system_prompt" => "You are concise.",
                 "plugins" => ["math_plugin", "math_plugin"]
               },
               available_plugins: [MathPlugin]
             )

    assert reason =~ "plugins must be unique"
  end

  test "rejects duplicate hook names within a stage in imported dynamic agent specs" do
    assert {:error, reason} =
             Moto.import_agent(
               %{
                 "name" => "duplicate_hook_agent",
                 "model" => "fast",
                 "system_prompt" => "You are concise.",
                 "hooks" => %{"before_turn" => ["inject_tenant", "inject_tenant"]}
               },
               available_hooks: [InjectTenantHook]
             )

    assert reason =~ "hook names must be unique"
  end

  test "rejects duplicate guardrail names within a stage in imported dynamic agent specs" do
    assert {:error, reason} =
             Moto.import_agent(
               %{
                 "name" => "duplicate_guardrail_agent",
                 "model" => "fast",
                 "system_prompt" => "You are concise.",
                 "guardrails" => %{"input" => ["safe_prompt", "safe_prompt"]}
               },
               available_guardrails: [SafePromptGuardrail]
             )

    assert reason =~ "guardrail names must be unique"
  end

  test "rejects unknown hook names in imported dynamic agent specs" do
    assert {:error, reason} =
             Moto.import_agent(
               %{
                 "name" => "bad_hook_agent",
                 "model" => "fast",
                 "system_prompt" => "You are concise.",
                 "hooks" => %{"before_turn" => ["does_not_exist"]}
               },
               available_hooks: [InjectTenantHook]
             )

    assert reason =~ "unknown hook"
  end

  test "rejects unknown guardrail names in imported dynamic agent specs" do
    assert {:error, reason} =
             Moto.import_agent(
               %{
                 "name" => "bad_guardrail_agent",
                 "model" => "fast",
                 "system_prompt" => "You are concise.",
                 "guardrails" => %{"input" => ["does_not_exist"]}
               },
               available_guardrails: [SafePromptGuardrail]
             )

    assert reason =~ "unknown guardrail"
  end

  test "rejects importing hooks without an available registry" do
    assert {:error, reason} =
             Moto.import_agent(%{
               "name" => "missing_hook_registry_agent",
               "model" => "fast",
               "system_prompt" => "You are concise.",
               "hooks" => %{"before_turn" => ["inject_tenant"]}
             })

    assert reason =~ "available_hooks registry"
  end

  test "rejects importing guardrails without an available registry" do
    assert {:error, reason} =
             Moto.import_agent(%{
               "name" => "missing_guardrail_registry_agent",
               "model" => "fast",
               "system_prompt" => "You are concise.",
               "guardrails" => %{"input" => ["safe_prompt"]}
             })

    assert reason =~ "available_guardrails registry"
  end

  test "rejects invalid request hook stages" do
    assert {:error, {:invalid_hook_stage, :bogus}} =
             Moto.Agent.prepare_chat_opts([hooks: [bogus: InjectTenantHook]], nil)
  end

  test "rejects invalid request hook refs" do
    assert {:error, {:invalid_hook, :before_turn, message}} =
             Moto.Agent.prepare_chat_opts([hooks: [before_turn: String]], nil)

    assert message =~ "not a valid Moto hook"
  end

  test "rejects invalid request guardrail stages" do
    assert {:error, {:invalid_guardrail_stage, :bogus}} =
             Moto.Agent.prepare_chat_opts([guardrails: [bogus: SafePromptGuardrail]], nil)
  end

  test "rejects invalid request guardrail refs" do
    assert {:error, {:invalid_guardrail, :input, message}} =
             Moto.Agent.prepare_chat_opts([guardrails: [input: String]], nil)

    assert message =~ "not a valid Moto guardrail"
  end

  test "rejects importing plugins without an available registry" do
    assert {:error, reason} =
             Moto.import_agent(%{
               "name" => "missing_plugin_registry_agent",
               "model" => "fast",
               "system_prompt" => "You are concise.",
               "plugins" => ["math_plugin"]
             })

    assert reason =~ "available_plugins registry"
  end

  test "rejects importing tools without an available registry" do
    assert {:error, reason} =
             Moto.import_agent(%{
               "name" => "missing_registry_agent",
               "model" => "fast",
               "system_prompt" => "You are concise.",
               "tools" => ["add_numbers"]
             })

    assert reason =~ "available_tools registry"
  end

  test "Moto.chat returns not_found for missing ids" do
    assert {:error, :not_found} = Moto.chat("missing-agent-id", "hello")
  end

  defp react_request(messages) when is_list(messages) do
    %{messages: messages, llm_opts: [], tools: %{}}
  end

  defp react_state do
    State.new("hello", nil, request_id: "req-test", run_id: "run-test")
  end

  defp react_config(request_transformer) do
    Config.new(
      model: :fast,
      system_prompt: nil,
      request_transformer: request_transformer,
      streaming: false
    )
  end

  defp new_runtime_agent(module) do
    module.new(id: "agent-#{System.unique_integer([:positive])}")
  end
end
