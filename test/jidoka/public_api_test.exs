defmodule JidokaTest.PublicAPITest do
  use ExUnit.Case, async: true

  alias JidokaTest.Workflow.ToolOnlyWorkflow

  test "top-level beta entrypoints are exported" do
    Code.ensure_loaded!(Jidoka)
    Code.ensure_loaded!(Jidoka.Workflow)

    assert function_exported?(Jidoka, :chat, 3)
    assert function_exported?(Jidoka, :start_agent, 2)
    assert function_exported?(Jidoka, :stop_agent, 1)
    assert function_exported?(Jidoka, :whereis, 2)
    assert function_exported?(Jidoka, :list_agents, 1)
    assert function_exported?(Jidoka, :model, 1)
    assert function_exported?(Jidoka, :format_error, 1)
    assert function_exported?(Jidoka, :import_agent, 2)
    assert function_exported?(Jidoka, :import_agent_file, 2)
    assert function_exported?(Jidoka, :encode_agent, 2)
    assert function_exported?(Jidoka, :inspect_agent, 1)
    assert function_exported?(Jidoka, :inspect_request, 1)
    assert function_exported?(Jidoka, :inspect_trace, 1)
    assert function_exported?(Jidoka, :inspect_trace, 2)
    assert function_exported?(Jidoka, :inspect_workflow, 1)
    assert function_exported?(Jidoka, :handoff_owner, 1)
    assert function_exported?(Jidoka, :reset_handoff, 1)
    assert function_exported?(Jidoka.Trace, :latest, 2)
    assert function_exported?(Jidoka.Trace, :for_request, 3)
    assert function_exported?(Jidoka.Trace, :list, 2)
    assert function_exported?(Jidoka.Trace, :events, 2)
    assert function_exported?(Jidoka.Trace, :spans, 2)
    assert function_exported?(Jidoka.Workflow, :run, 3)

    refute function_exported?(Jidoka, :run, 3)
  end

  test "generated beta entrypoints are exported" do
    Code.ensure_loaded!(JidokaTest.ChatAgent)
    Code.ensure_loaded!(ToolOnlyWorkflow)

    assert function_exported?(JidokaTest.ChatAgent, :start_link, 1)
    assert function_exported?(JidokaTest.ChatAgent, :chat, 3)
    assert function_exported?(JidokaTest.ChatAgent, :id, 0)

    assert function_exported?(ToolOnlyWorkflow, :run, 2)
    assert function_exported?(ToolOnlyWorkflow, :id, 0)
  end

  test "workflow inspection omits raw Runic graph internals" do
    assert {:ok, inspection} = Jidoka.inspect_workflow(ToolOnlyWorkflow)

    refute Map.has_key?(inspection, :graph)
    refute Map.has_key?(inspection, :node_map)
    refute Map.has_key?(inspection, :execution_summary)
  end
end
