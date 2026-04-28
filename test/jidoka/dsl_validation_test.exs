defmodule JidokaTest.DslValidationTest do
  use JidokaTest.Support.Case, async: false

  alias JidokaTest.{InjectTenantHook, SafePromptGuardrail}

  test "rejects old keyword opts in favor of the DSL" do
    assert_raise CompileError, ~r/Jidoka.Agent now uses a Spark DSL/, fn ->
      Code.compile_string("""
      defmodule JidokaTest.InvalidKeywordAgent do
        use Jidoka.Agent,
          instructions: "This should fail."
      end
      """)
    end
  end

  test "rejects legacy agent.model placement" do
    assert_dsl_error(~r/agent.model.*defaults/s, """
    agent do
      id :legacy_model_agent
      model :fast
    end

    defaults do
      instructions "This should fail."
    end
    """)
  end

  test "rejects legacy agent.system_prompt placement" do
    assert_dsl_error(~r/agent.system_prompt.*instructions/s, """
    agent do
      id :legacy_prompt_agent
      system_prompt "This should fail."
    end

    defaults do
      instructions "This should fail."
    end
    """)
  end

  test "rejects legacy top-level sections" do
    for {section, body} <- [
          {"memory", "mode :conversation"},
          {"tools", "tool JidokaTest.AddNumbers"},
          {"skills", "skill \"math-discipline\""},
          {"plugins", "plugin JidokaTest.MathPlugin"},
          {"subagents", "subagent JidokaTest.ResearchSpecialist"},
          {"hooks", "before_turn JidokaTest.InjectTenantHook"},
          {"guardrails", "input JidokaTest.SafePromptGuardrail"}
        ] do
      assert_dsl_error(~r/Top-level `#{section} do .*` is not valid/s, """
      agent do
        id :legacy_#{section}_agent
      end

      defaults do
        instructions "This should fail."
      end

      #{section} do
        #{body}
      end
      """)
    end
  end

  test "requires lower snake case agent ids" do
    assert_dsl_error(~r/agent.id.*lower snake case/s, """
    agent do
      id "Bad-ID"
    end

    defaults do
      instructions "This should fail."
    end
    """)
  end

  test "requires agent ids" do
    assert_dsl_error(~r/agent.id.*required/s, """
    agent do
      description "Missing id"
    end

    defaults do
      instructions "This should fail."
    end
    """)
  end

  test "requires defaults.instructions" do
    assert_dsl_error(~r/defaults.instructions.*required/s, """
    agent do
      id :missing_instructions_agent
    end
    """)
  end

  test "rejects invalid instructions resolvers" do
    assert_dsl_error(~r/instructions does not support anonymous functions/, """
    agent do
      id :invalid_instructions_agent
    end

    defaults do
      instructions fn _input -> "This should fail." end
    end
    """)
  end

  test "rejects invalid model configuration" do
    assert_dsl_error(~r/invalid model input 123/, """
    agent do
      id :invalid_model_agent
    end

    defaults do
      model 123
      instructions "This should fail."
    end
    """)
  end

  test "rejects non-map agent schemas" do
    assert_dsl_error(~r/agent schema must be a Zoi map\/object schema/, """
    agent do
      id :invalid_context_schema_agent
      schema Zoi.string()
    end

    defaults do
      instructions "This should fail."
    end
    """)
  end

  test "validates structured output contracts" do
    assert_dsl_error(~r/output schema must be a Zoi object\/map schema/, """
    agent do
      id :invalid_output_schema_agent

      output do
        schema Zoi.string()
      end
    end

    defaults do
      instructions "This should fail."
    end
    """)

    assert_dsl_error(~r/output retries must be a non-negative integer/, """
    agent do
      id :invalid_output_retries_agent

      output do
        schema Zoi.object(%{summary: Zoi.string()})
        retries -1
      end
    end

    defaults do
      instructions "This should fail."
    end
    """)

    assert_dsl_error(~r/Zoi object\/map schema in the Elixir DSL/, """
    agent do
      id :json_schema_output_agent

      output do
        schema %{"type" => "object", "properties" => %{"summary" => %{"type" => "string"}}}
      end
    end

    defaults do
      instructions "This should fail."
    end
    """)
  end

  test "validates memory lifecycle configuration" do
    assert_dsl_error(~r/memory namespace must be :per_agent, :shared with shared_namespace/, """
    agent do
      id :invalid_memory_namespace_agent
    end

    defaults do
      instructions "This should fail."
    end

    lifecycle do
      memory do
        namespace :shared
      end
    end
    """)

    assert_dsl_error(~r/shared_namespace is only valid when namespace is :shared/, """
    agent do
      id :invalid_shared_namespace_agent
    end

    defaults do
      instructions "This should fail."
    end

    lifecycle do
      memory do
        namespace :per_agent
        shared_namespace "wrong"
      end
    end
    """)

    assert_dsl_error(~r/memory context namespace key is not declared/, """
    agent do
      id :invalid_memory_context_key_agent
      schema Zoi.object(%{tenant: Zoi.string() |> Zoi.optional()})
    end

    defaults do
      instructions "This should fail."
    end

    lifecycle do
      memory do
        namespace {:context, :session}
      end
    end
    """)
  end

  test "rejects duplicate capability names across sources" do
    assert_dsl_error(~r/duplicate tool names.*multiply_numbers/s, """
    agent do
      id :duplicate_capability_agent
    end

    defaults do
      instructions "This should fail."
    end

    capabilities do
      tool JidokaTest.MultiplyNumbers
      plugin JidokaTest.MathPlugin
    end
    """)
  end

  test "rejects duplicate lifecycle refs within stages" do
    assert_dsl_error(~r/hook .*defined more than once/, """
    agent do
      id :duplicate_hook_agent
    end

    defaults do
      instructions "This should fail."
    end

    lifecycle do
      before_turn JidokaTest.InjectTenantHook
      before_turn JidokaTest.InjectTenantHook
    end
    """)

    assert_dsl_error(~r/guardrail .*defined more than once/, """
    agent do
      id :duplicate_guardrail_agent
    end

    defaults do
      instructions "This should fail."
    end

    lifecycle do
      input_guardrail JidokaTest.SafePromptGuardrail
      input_guardrail JidokaTest.SafePromptGuardrail
    end
    """)
  end

  test "rejects invalid capability modules" do
    assert_dsl_error(~r/not a valid Jidoka tool/, """
    agent do
      id :invalid_tool_agent
    end

    defaults do
      instructions "This should fail."
    end

    capabilities do
      tool String
    end
    """)
  end

  test "rejects invalid request hook stages" do
    assert {:error, %Jidoka.Error.ValidationError{} = error} =
             Jidoka.Agent.prepare_chat_opts([hooks: [bogus: InjectTenantHook]], nil)

    assert error.field == :hooks
    assert error.details.reason == :invalid_hook_stage
    assert error.details.stage == :bogus
  end

  test "rejects invalid request hook refs" do
    assert {:error, %Jidoka.Error.ValidationError{} = error} =
             Jidoka.Agent.prepare_chat_opts([hooks: [before_turn: String]], nil)

    assert error.field == :hooks
    assert error.details.reason == :invalid_hook
    assert error.details.stage == :before_turn
    assert error.message =~ "not a valid Jidoka hook"
  end

  test "rejects invalid request guardrail stages" do
    assert {:error, %Jidoka.Error.ValidationError{} = error} =
             Jidoka.Agent.prepare_chat_opts([guardrails: [bogus: SafePromptGuardrail]], nil)

    assert error.field == :guardrails
    assert error.details.reason == :invalid_guardrail_stage
    assert error.details.stage == :bogus
  end

  test "rejects invalid request guardrail refs" do
    assert {:error, %Jidoka.Error.ValidationError{} = error} =
             Jidoka.Agent.prepare_chat_opts([guardrails: [input: String]], nil)

    assert error.field == :guardrails
    assert error.details.reason == :invalid_guardrail
    assert error.details.stage == :input
    assert error.message =~ "not a valid Jidoka guardrail"
  end

  test "rejects NimbleOptions schemas in Jidoka.Tool" do
    assert_raise CompileError, ~r/must use a Zoi schema for schema\/0/, fn ->
      Code.compile_string("""
      defmodule JidokaTest.NimbleSchemaTool do
        use Jidoka.Tool,
          schema: [a: [type: :integer, required: true]]

        @impl true
        def run(params, _context), do: {:ok, params}
      end
      """)
    end
  end

  test "rejects raw JSON Schema maps in Jidoka.Tool" do
    assert_raise CompileError, ~r/must use a Zoi schema for schema\/0/, fn ->
      Code.compile_string("""
      defmodule JidokaTest.JsonSchemaTool do
        use Jidoka.Tool,
          schema: %{"type" => "object", "properties" => %{"a" => %{"type" => "integer"}}}

        @impl true
        def run(params, _context), do: {:ok, params}
      end
      """)
    end
  end

  defp assert_dsl_error(pattern, body) do
    module = Module.concat(JidokaTest.DynamicDsl, "Agent#{System.unique_integer([:positive])}")

    source = """
    defmodule #{inspect(module)} do
      use Jidoka.Agent

      #{body}
    end
    """

    assert_raise Spark.Error.DslError, pattern, fn ->
      Code.compile_string(source)
    end
  end
end
