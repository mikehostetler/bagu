defmodule MotoTest.DslValidationTest do
  use MotoTest.Support.Case, async: false

  alias MotoTest.{InjectTenantHook, SafePromptGuardrail}

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

  test "rejects non-map agent schemas at compile time" do
    assert_raise Spark.Error.DslError, ~r/agent schema must be a Zoi map\/object schema/, fn ->
      Code.compile_string("""
      defmodule MotoTest.InvalidContextSchemaAgent do
        use Moto.Agent

        agent do
          system_prompt "This should fail."
          schema Zoi.string()
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

  test "rejects invalid skill refs at compile time" do
    assert_raise Spark.Error.DslError, ~r/invalid skill name/, fn ->
      Code.compile_string("""
      defmodule MotoTest.InvalidSkillRefAgent do
        use Moto.Agent

        agent do
          system_prompt "This should fail."
        end

        skills do
          skill "Bad Skill"
        end
      end
      """)
    end
  end

  test "rejects invalid skill load paths at compile time" do
    assert_raise Spark.Error.DslError, ~r/skill load paths must not be empty/, fn ->
      Code.compile_string("""
      defmodule MotoTest.InvalidSkillPathAgent do
        use Moto.Agent

        agent do
          system_prompt "This should fail."
        end

        skills do
          skill "valid-skill"
          load_path "   "
        end
      end
      """)
    end
  end

  test "rejects invalid subagent modules at compile time" do
    assert_raise Spark.Error.DslError, ~r/not a valid Moto subagent/, fn ->
      Code.compile_string("""
      defmodule MotoTest.InvalidSubagentAgent do
        use Moto.Agent

        agent do
          system_prompt "This should fail."
        end

        subagents do
          subagent String
        end
      end
      """)
    end
  end

  test "rejects duplicate subagent names at compile time" do
    assert_raise Spark.Error.DslError, ~r/subagent names must be unique/, fn ->
      Code.compile_string("""
      defmodule MotoTest.DuplicateSubagentAgent do
        use Moto.Agent

        agent do
          system_prompt "This should fail."
        end

        subagents do
          subagent MotoTest.ResearchSpecialist
          subagent MotoTest.ReviewSpecialist, as: "research_agent"
        end
      end
      """)
    end
  end

  test "rejects invalid subagent target shapes at compile time" do
    assert_raise Spark.Error.DslError, ~r/subagent target must be/, fn ->
      Code.compile_string("""
      defmodule MotoTest.InvalidSubagentTargetAgent do
        use Moto.Agent

        agent do
          system_prompt "This should fail."
        end

        subagents do
          subagent MotoTest.ResearchSpecialist, target: {:peer, 123}
        end
      end
      """)
    end
  end

  test "rejects invalid subagent timeouts at compile time" do
    assert_raise Spark.Error.DslError, ~r/subagent timeout must be a positive integer/, fn ->
      Code.compile_string("""
      defmodule MotoTest.InvalidSubagentTimeoutAgent do
        use Moto.Agent

        agent do
          system_prompt "This should fail."
        end

        subagents do
          subagent MotoTest.ResearchSpecialist, timeout: 0
        end
      end
      """)
    end
  end

  test "rejects invalid subagent context forwarding policies at compile time" do
    assert_raise Spark.Error.DslError, ~r/subagent forward_context must be/, fn ->
      Code.compile_string("""
      defmodule MotoTest.InvalidSubagentForwardContextAgent do
        use Moto.Agent

        agent do
          system_prompt "This should fail."
        end

        subagents do
          subagent MotoTest.ResearchSpecialist, forward_context: :everything
        end
      end
      """)
    end
  end

  test "rejects invalid subagent result modes at compile time" do
    assert_raise Spark.Error.DslError, ~r/subagent result must be :text or :structured/, fn ->
      Code.compile_string("""
      defmodule MotoTest.InvalidSubagentResultAgent do
        use Moto.Agent

        agent do
          system_prompt "This should fail."
        end

        subagents do
          subagent MotoTest.ResearchSpecialist, result: :json
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
end
