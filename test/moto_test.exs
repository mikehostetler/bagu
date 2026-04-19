defmodule MotoTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  alias Moto.DynamicAgent
  alias MotoTest.Support.{Accounts, AshResourceAgent, User}

  defmodule ChatAgent do
    use Moto.Agent

    agent do
      model(:fast)
      system_prompt("You are a concise assistant.")
    end
  end

  defmodule StringModelAgent do
    use Moto.Agent

    agent do
      model("openai:gpt-4.1")
      system_prompt("You are a concise assistant.")
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

  test "exposes configured plugin modules and names" do
    assert PluginAgent.plugins() == [MathPlugin]
    assert PluginAgent.plugin_names() == ["math_plugin"]
  end

  test "merges plugin actions into the agent tool registry" do
    assert PluginAgent.tools() == [MultiplyNumbers]
    assert PluginAgent.tool_names() == ["multiply_numbers"]
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

  test "requires actor in tool_context for ash_resource agents" do
    assert {:ok, pid} = AshResourceAgent.start_link(id: "ash-resource-agent-test")

    try do
      assert {:error, {:missing_tool_context, :actor}} =
               AshResourceAgent.chat(pid, "List users.")
    after
      :ok = Moto.stop_agent(pid)
    end
  end

  test "injects ash domain into tool_context for ash_resource agents" do
    assert {:ok, opts} =
             Moto.Agent.prepare_chat_opts(
               [tool_context: %{actor: %{id: "user-1"}}],
               %{domain: Accounts, require_actor?: true}
             )

    assert Keyword.get(opts, :tool_context) == %{actor: %{id: "user-1"}, domain: Accounts}
  end

  test "rejects mismatched tool_context domain for ash_resource agents" do
    assert {:error, {:invalid_tool_context, {:domain_mismatch, Accounts, :other_domain}}} =
             Moto.Agent.prepare_chat_opts(
               [tool_context: %{actor: %{id: "user-1"}, domain: :other_domain}],
               %{domain: Accounts, require_actor?: true}
             )
  end

  test "imports a constrained dynamic agent from JSON" do
    json = """
    {
      "name": "json_agent",
      "model": "fast",
      "system_prompt": "You are a concise assistant.",
      "tools": ["add_numbers"],
      "plugins": ["math_plugin"]
    }
    """

    assert {:ok, %DynamicAgent{} = agent} =
             Moto.import_agent(
               json,
               available_tools: [AddNumbers],
               available_plugins: [MathPlugin]
             )

    assert {:ok, encoded} = Moto.encode_agent(agent, format: :json)
    assert encoded =~ "\"name\": \"json_agent\""
    assert encoded =~ "\"model\": \"fast\""
    assert encoded =~ "\"tools\": ["
    assert encoded =~ "\"plugins\": ["
    assert agent.tool_modules == [AddNumbers, MultiplyNumbers]
    assert agent.plugin_modules == [MathPlugin]
  end

  test "imports a constrained dynamic agent from YAML" do
    yaml = """
    name: "yaml_agent"
    model:
      provider: "openai"
      id: "gpt-4.1"
    system_prompt: |-
      You are a concise assistant.
    tools:
      - "add_numbers"
    plugins:
      - "math_plugin"
    """

    assert {:ok, %DynamicAgent{} = agent} =
             Moto.import_agent(
               yaml,
               format: :yaml,
               available_tools: [AddNumbers],
               available_plugins: [MathPlugin]
             )

    assert {:ok, encoded} = Moto.encode_agent(agent, format: :yaml)
    assert encoded =~ "name: \"yaml_agent\""
    assert encoded =~ "provider: \"openai\""
    assert encoded =~ "- \"add_numbers\""
    assert encoded =~ "- \"math_plugin\""
    assert agent.tool_modules == [AddNumbers, MultiplyNumbers]
  end

  test "imports a constrained dynamic agent from file" do
    path = Path.join(System.tmp_dir!(), "moto-dynamic-agent.json")

    on_exit(fn -> File.rm(path) end)

    File.write!(
      path,
      ~s({"name":"file_agent","model":"fast","system_prompt":"You are concise.","tools":["add_numbers"],"plugins":["math_plugin"]})
    )

    assert {:ok, %DynamicAgent{} = agent} =
             Moto.import_agent_file(
               path,
               available_tools: [AddNumbers],
               available_plugins: [MathPlugin]
             )

    assert agent.tool_modules == [AddNumbers, MultiplyNumbers]
    assert agent.plugin_modules == [MathPlugin]
  end

  test "starts an imported dynamic agent under the shared runtime" do
    json = """
    {
      "name": "runtime_agent",
      "model": "fast",
      "system_prompt": "You are a concise assistant.",
      "tools": ["add_numbers"],
      "plugins": ["math_plugin"]
    }
    """

    assert {:ok, %DynamicAgent{} = agent} =
             Moto.import_agent(
               json,
               available_tools: [AddNumbers],
               available_plugins: [MathPlugin]
             )

    assert {:ok, pid} = Moto.start_agent(agent, id: "dynamic-agent-test")
    assert is_pid(pid)
    assert Moto.whereis("dynamic-agent-test") == pid
    assert :ok = Moto.stop_agent(pid)
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
end
