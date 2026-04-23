defmodule BaguTest.PublicAPITest do
  use ExUnit.Case, async: true

  alias BaguTest.Workflow.ToolOnlyWorkflow

  test "top-level beta entrypoints are exported" do
    Code.ensure_loaded!(Bagu)
    Code.ensure_loaded!(Bagu.Workflow)

    assert function_exported?(Bagu, :chat, 3)
    assert function_exported?(Bagu, :start_agent, 2)
    assert function_exported?(Bagu, :stop_agent, 1)
    assert function_exported?(Bagu, :whereis, 2)
    assert function_exported?(Bagu, :list_agents, 1)
    assert function_exported?(Bagu, :model, 1)
    assert function_exported?(Bagu, :format_error, 1)
    assert function_exported?(Bagu, :import_agent, 2)
    assert function_exported?(Bagu, :import_agent_file, 2)
    assert function_exported?(Bagu, :encode_agent, 2)
    assert function_exported?(Bagu, :inspect_agent, 1)
    assert function_exported?(Bagu, :inspect_request, 1)
    assert function_exported?(Bagu, :inspect_workflow, 1)
    assert function_exported?(Bagu.Workflow, :run, 3)

    refute function_exported?(Bagu, :run, 3)
  end

  test "generated beta entrypoints are exported" do
    Code.ensure_loaded!(BaguTest.ChatAgent)
    Code.ensure_loaded!(ToolOnlyWorkflow)

    assert function_exported?(BaguTest.ChatAgent, :start_link, 1)
    assert function_exported?(BaguTest.ChatAgent, :chat, 3)
    assert function_exported?(BaguTest.ChatAgent, :id, 0)

    assert function_exported?(ToolOnlyWorkflow, :run, 2)
    assert function_exported?(ToolOnlyWorkflow, :id, 0)
  end

  test "workflow inspection omits raw Runic graph internals" do
    assert {:ok, inspection} = Bagu.inspect_workflow(ToolOnlyWorkflow)

    refute Map.has_key?(inspection, :graph)
    refute Map.has_key?(inspection, :node_map)
    refute Map.has_key?(inspection, :execution_summary)
  end
end
