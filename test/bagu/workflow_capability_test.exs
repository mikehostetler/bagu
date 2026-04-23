defmodule BaguTest.WorkflowCapabilityTest do
  use BaguTest.Support.Case, async: false

  alias BaguTest.WorkflowCapability.{
    ContextAgent,
    FailingAgent,
    MathAgent,
    MathWorkflow
  }

  test "compiled agents expose workflows as generated tool modules" do
    assert MathAgent.workflow_names() == ["run_math"]
    assert [%Bagu.Workflow.Capability{name: "run_math", workflow: MathWorkflow}] = MathAgent.workflows()
    assert "run_math" in MathAgent.tool_names()

    tool = workflow_tool(MathAgent, "run_math")

    assert tool.schema() == MathWorkflow.input_schema()

    assert {:ok, %{output: %{value: 12}, workflow: metadata}} =
             tool.run(%{value: 5}, %{})

    assert metadata.name == "run_math"
    assert metadata.outcome == :ok
    assert metadata.input_keys == ["value"]
  end

  test "workflow capabilities forward selected public context" do
    tool = workflow_tool(ContextAgent, "context_echo")

    assert {:ok, %{output: "schemas:done"}} =
             tool.run(%{topic: "schemas"}, %{suffix: "done", secret: "hidden"})
  end

  test "workflow capability returns Bagu validation errors for missing context refs" do
    tool = workflow_tool(ContextAgent, "context_echo")

    assert {:error, %Bagu.Error.ValidationError{} = error} =
             tool.run(%{topic: "schemas"}, %{})

    assert error.message =~ "Missing workflow context key `suffix`"
    assert Bagu.format_error(error) =~ "Missing workflow context key `suffix`"
  end

  test "workflow capability returns Bagu validation errors for invalid input" do
    tool = workflow_tool(MathAgent, "run_math")

    assert {:error, %Bagu.Error.ValidationError{} = error} =
             tool.run(%{value: "bad"}, %{})

    assert error.message =~ "Invalid workflow input"
  end

  test "workflow capability returns Bagu execution errors for step failures" do
    tool = workflow_tool(FailingAgent, "fail_workflow")

    assert {:error, %Bagu.Error.ExecutionError{} = error} =
             tool.run(%{reason: "boom"}, %{})

    assert error.message =~ "Workflow workflow_capability_failure step fail failed"
    assert error.details.step == :fail
  end

  test "workflow capability records request metadata when request context is present" do
    tool = workflow_tool(MathAgent, "run_math")
    request_id = "workflow-capability-#{System.unique_integer([:positive])}"

    assert {:ok, %{output: %{value: 12}}} =
             tool.run(%{value: 5}, %{
               Bagu.Subagent.server_key() => self(),
               Bagu.Subagent.request_id_key() => request_id
             })

    assert [%{name: "run_math", outcome: :ok, output_preview: preview}] =
             Bagu.Workflow.Capability.request_calls(self(), request_id)

    assert preview =~ "value"
  end

  test "workflow capability names conflict with other tool-like capabilities" do
    assert_raise Spark.Error.DslError, ~r/duplicate tool names.*workflow_capability_math/s, fn ->
      Code.compile_string("""
      defmodule BaguTest.WorkflowCapability.DuplicateWorkflowToolAgent do
        use Bagu.Agent

        agent do
          id :duplicate_workflow_tool_agent
        end

        defaults do
          instructions "This should fail."
        end

        capabilities do
          tool BaguTest.WorkflowCapability.DuplicateNameTool
          workflow BaguTest.WorkflowCapability.MathWorkflow
        end
      end
      """)
    end
  end

  test "Bagu.run/3 is not part of the beta public API" do
    refute function_exported?(Bagu, :run, 3)
  end

  defp workflow_tool(agent_module, name) do
    Enum.find(agent_module.tools(), fn tool_module ->
      Code.ensure_loaded?(tool_module) and function_exported?(tool_module, :name, 0) and tool_module.name() == name
    end)
  end
end
