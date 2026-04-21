defmodule MotoTest.ImportedAgentTest do
  use MotoTest.Support.Case, async: false

  alias Moto.DynamicAgent
  alias Moto.DynamicAgent.Spec, as: DynamicSpec

  alias MotoTest.{
    AddNumbers,
    ApproveLargeMathToolGuardrail,
    InjectTenantHook,
    InterruptBeforeHook,
    MathPlugin,
    ModuleMathSkill,
    NormalizeReplyHook,
    NotifyOpsHook,
    ResearchSpecialist,
    RestrictRefundsHook,
    ReviewSpecialist,
    SafePromptGuardrail,
    SafeReplyGuardrail
  }

  test "imports a constrained imported agent from JSON" do
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

    assert {:ok, %ImportedAgent{} = agent} =
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
    assert agent.tool_modules == [AddNumbers, MotoTest.MultiplyNumbers]
    assert agent.plugin_modules == [MathPlugin]
    assert agent.hook_modules.before_turn == [InjectTenantHook, RestrictRefundsHook]
    assert agent.hook_modules.after_turn == [NormalizeReplyHook]
    assert agent.hook_modules.on_interrupt == [NotifyOpsHook]
    assert agent.guardrail_modules.input == [SafePromptGuardrail]
    assert agent.guardrail_modules.output == [SafeReplyGuardrail]
    assert agent.guardrail_modules.tool == [ApproveLargeMathToolGuardrail]
  end

  test "imports skills and mcp tool sync settings" do
    assert {:ok, %ImportedAgent{} = agent} =
             Moto.import_agent(
               %{
                 "name" => "skills_agent",
                 "model" => "fast",
                 "system_prompt" => "You are skill-aware.",
                 "skills" => ["module-math-skill"],
                 "mcp_tools" => [%{"endpoint" => "github", "prefix" => "github_"}]
               },
               available_skills: [ModuleMathSkill]
             )

    assert agent.skill_refs == [ModuleMathSkill]
    assert agent.mcp_tools == [%{endpoint: "github", prefix: "github_"}]
    assert Enum.member?(agent.tool_modules, MotoTest.MultiplyNumbers)

    assert {:ok, encoded_json} = Moto.encode_agent(agent, format: :json)
    assert encoded_json =~ "\"skills\""
    assert encoded_json =~ "\"mcp_tools\""
  end

  test "imports runtime skill paths relative to the spec file" do
    root =
      Path.join(System.tmp_dir!(), "moto-imported-skill-#{System.unique_integer([:positive])}")

    skill_dir = Path.join(root, "skills/math-discipline")
    spec_dir = Path.join(root, "agents")
    spec_path = Path.join(spec_dir, "agent.json")

    File.mkdir_p!(skill_dir)
    File.mkdir_p!(spec_dir)

    File.write!(
      Path.join(skill_dir, "SKILL.md"),
      """
      ---
      name: math-discipline
      description: Runtime skill for imported Moto agents.
      allowed-tools: add_numbers
      ---

      # Imported Math Discipline

      Use the add_numbers tool for arithmetic.
      """
    )

    File.write!(
      spec_path,
      Jason.encode!(%{
        name: "runtime_skill_agent",
        model: "fast",
        system_prompt: "You are concise.",
        skills: ["math-discipline"],
        skill_paths: ["../skills"]
      })
    )

    on_exit(fn -> File.rm_rf!(root) end)

    assert {:ok, %ImportedAgent{} = agent} = Moto.import_agent_file(spec_path)
    assert agent.skill_refs == ["math-discipline"]
    assert agent.spec.skill_paths == [Path.expand("../skills", spec_dir)]
  end

  test "keeps dynamic-agent compatibility wrappers working" do
    assert {:ok, %DynamicSpec{} = spec} =
             DynamicSpec.new(
               %{
                 "name" => "compat_agent",
                 "model" => "fast",
                 "system_prompt" => "You are concise.",
                 "tools" => ["add_numbers"]
               },
               available_tools: [AddNumbers]
             )

    assert {:ok, %DynamicAgent{} = agent} =
             DynamicAgent.import(spec, available_tools: [AddNumbers])

    assert {:ok, encoded} = Moto.encode_agent(agent, format: :json)
    assert encoded =~ "\"name\": \"compat_agent\""

    assert {:ok, pid} = Moto.start_agent(agent, id: "dynamic-agent-compat")
    assert Moto.whereis("dynamic-agent-compat") == pid
    assert :ok = Moto.stop_agent(pid)
  end

  test "imports a constrained imported agent from YAML" do
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

    assert {:ok, %ImportedAgent{} = agent} =
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
    assert agent.tool_modules == [AddNumbers, MotoTest.MultiplyNumbers]
    assert agent.spec.context == %{"tenant" => "yaml", "channel" => "imported"}
    assert agent.hook_modules.before_turn == [InjectTenantHook, RestrictRefundsHook]
    assert agent.guardrail_modules.tool == [ApproveLargeMathToolGuardrail]
  end

  test "imports a constrained imported agent from file" do
    path = Path.join(System.tmp_dir!(), "moto-imported-agent.json")

    on_exit(fn -> File.rm(path) end)

    File.write!(
      path,
      ~s({"name":"file_agent","model":"fast","system_prompt":"You are concise.","context":{"tenant":"file","channel":"imported"},"tools":["add_numbers"],"plugins":["math_plugin"],"hooks":{"before_turn":["inject_tenant"],"after_turn":["normalize_reply"],"on_interrupt":["notify_ops"]},"guardrails":{"input":["safe_prompt"],"output":["safe_reply"],"tool":["approve_large_math_tool"]}})
    )

    assert {:ok, %ImportedAgent{} = agent} =
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

    assert agent.tool_modules == [AddNumbers, MotoTest.MultiplyNumbers]
    assert agent.plugin_modules == [MathPlugin]
    assert agent.spec.context == %{"tenant" => "file", "channel" => "imported"}
    assert agent.hook_modules.before_turn == [InjectTenantHook]
    assert agent.guardrail_modules.input == [SafePromptGuardrail]
  end

  test "imports constrained subagents and compiles them into generated tool modules" do
    assert {:ok, %ImportedAgent{} = agent} =
             Moto.import_agent(
               %{
                 "name" => "subagent_import_agent",
                 "model" => "fast",
                 "system_prompt" => "You can delegate.",
                 "subagents" => [
                   %{"agent" => "research_agent"},
                   %{
                     "agent" => "review_agent",
                     "as" => "review_specialist",
                     "description" => "Ask the review specialist",
                     "target" => "peer",
                     "peer_id_context_key" => "review_peer_id"
                   }
                 ]
               },
               available_subagents: [ResearchSpecialist, ReviewSpecialist]
             )

    assert Enum.map(agent.subagents, & &1.name) == ["research_agent", "review_specialist"]

    assert Enum.sort(Enum.map(agent.tool_modules, & &1.name())) == [
             "research_agent",
             "review_specialist"
           ]

    research_tool =
      Enum.find(agent.tool_modules, fn tool_module -> tool_module.name() == "research_agent" end)

    assert {:ok, %{result: "research:Imported task:tenant=imported:depth=1"}} =
             research_tool.run(%{task: "Imported task"}, %{tenant: "imported"})

    assert {:ok, encoded_json} = Moto.encode_agent(agent, format: :json)
    assert encoded_json =~ "\"subagents\""

    assert {:ok, encoded_yaml} = Moto.encode_agent(agent, format: :yaml)
    assert encoded_yaml =~ "subagents:"
    assert encoded_yaml =~ "agent: \"research_agent\""
  end

  test "starts an imported agent under the shared runtime" do
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

    assert {:ok, %ImportedAgent{} = agent} =
             Moto.import_agent(
               json,
               available_tools: [AddNumbers],
               available_plugins: [MathPlugin],
               available_hooks: [InterruptBeforeHook, NotifyOpsHook],
               available_guardrails: [SafePromptGuardrail]
             )

    assert {:ok, pid} = Moto.start_agent(agent, id: "imported-agent-test")
    assert is_pid(pid)
    assert Moto.whereis("imported-agent-test") == pid
    assert :ok = Moto.stop_agent(pid)
  end

  test "merges imported default context into runtime requests" do
    assert {:ok, %ImportedAgent{} = agent} =
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

    assert Moto.Context.strip_internal(params.tool_context) == %{
             "tenant" => "imported",
             "channel" => "json",
             session: "runtime"
           }

    assert Moto.Context.strip_internal(params.runtime_context) == %{
             "tenant" => "imported",
             "channel" => "json",
             session: "runtime"
           }
  end

  test "imports and round-trips memory settings in constrained imported agent specs" do
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

    assert {:ok, %ImportedAgent{} = agent} = Moto.import_agent(json)

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

  test "imported agents retrieve and capture memory across turns" do
    assert {:ok, %ImportedAgent{} = agent} =
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

  test "rejects unexpected keys in imported agent specs" do
    assert {:error, reason} =
             Moto.import_agent(%{
               "name" => "bad_agent",
               "model" => "fast",
               "system_prompt" => "You are concise.",
               "extra" => true
             })

    assert reason =~ "unrecognized"
  end

  test "rejects unknown bare model aliases in imported agent specs" do
    assert {:error, reason} =
             Moto.import_agent(%{
               "name" => "bad_model_agent",
               "model" => "does_not_exist",
               "system_prompt" => "You are concise."
             })

    assert reason =~ "known alias string"
  end

  test "rejects unknown tool names in imported agent specs" do
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

  test "rejects duplicate tool names in imported agent specs" do
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

  test "rejects unknown plugin names in imported agent specs" do
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

  test "rejects duplicate plugin names in imported agent specs" do
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

  test "rejects duplicate hook names within a stage in imported agent specs" do
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

  test "rejects duplicate guardrail names within a stage in imported agent specs" do
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

  test "rejects unknown hook names in imported agent specs" do
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

  test "rejects unknown guardrail names in imported agent specs" do
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

  test "rejects imported subagents without an available registry" do
    assert {:error, reason} =
             Moto.import_agent(%{
               "name" => "missing_subagent_registry",
               "model" => "fast",
               "system_prompt" => "You can delegate.",
               "subagents" => [%{"agent" => "research_agent"}]
             })

    assert reason =~ "available_subagents registry"
  end

  test "rejects imported subagents with duplicate published names" do
    assert {:error, reason} =
             Moto.import_agent(
               %{
                 "name" => "duplicate_subagent_import",
                 "model" => "fast",
                 "system_prompt" => "You can delegate.",
                 "subagents" => [
                   %{"agent" => "research_agent"},
                   %{"agent" => "review_agent", "as" => "research_agent"}
                 ]
               },
               available_subagents: [ResearchSpecialist, ReviewSpecialist]
             )

    assert reason =~ "subagent names must be unique"
  end

  test "rejects imported subagents with invalid peer configuration" do
    assert {:error, reason} =
             Moto.import_agent(
               %{
                 "name" => "invalid_peer_import",
                 "model" => "fast",
                 "system_prompt" => "You can delegate.",
                 "subagents" => [
                   %{"agent" => "research_agent", "target" => "peer"}
                 ]
               },
               available_subagents: [ResearchSpecialist]
             )

    assert reason =~ "subagent target must be"
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
end
