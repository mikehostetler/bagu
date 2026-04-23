defmodule BaguTest.WorkflowCapability.AddOne do
  @moduledoc false

  use Bagu.Tool,
    name: "workflow_capability_add_one",
    description: "Adds one to a workflow value.",
    schema: Zoi.object(%{value: Zoi.integer()})

  @impl true
  def run(%{value: value}, _context), do: {:ok, %{value: value + 1}}
end

defmodule BaguTest.WorkflowCapability.DoubleValue do
  @moduledoc false

  use Bagu.Tool,
    name: "workflow_capability_double_value",
    description: "Doubles a workflow value.",
    schema: Zoi.object(%{value: Zoi.integer()})

  @impl true
  def run(%{value: value}, _context), do: {:ok, %{value: value * 2}}
end

defmodule BaguTest.WorkflowCapability.Fail do
  @moduledoc false

  use Bagu.Tool,
    name: "workflow_capability_fail",
    description: "Fails with a caller-provided reason.",
    schema: Zoi.object(%{reason: Zoi.string()})

  @impl true
  def run(%{reason: reason}, _context), do: {:error, reason}
end

defmodule BaguTest.WorkflowCapability.Fns do
  @moduledoc false

  def echo_context(%{topic: topic, suffix: suffix}, _context), do: {:ok, "#{topic}:#{suffix}"}
end

defmodule BaguTest.WorkflowCapability.MathWorkflow do
  @moduledoc false

  use Bagu.Workflow

  workflow do
    id :workflow_capability_math
    description "Adds one and doubles the result."
    input Zoi.object(%{value: Zoi.integer()})
  end

  steps do
    tool :add, BaguTest.WorkflowCapability.AddOne, input: %{value: input(:value)}
    tool :double, BaguTest.WorkflowCapability.DoubleValue, input: from(:add)
  end

  output from(:double)
end

defmodule BaguTest.WorkflowCapability.ContextWorkflow do
  @moduledoc false

  use Bagu.Workflow

  workflow do
    id :workflow_capability_context
    input Zoi.object(%{topic: Zoi.string()})
  end

  steps do
    function :echo, {BaguTest.WorkflowCapability.Fns, :echo_context, 2},
      input: %{
        topic: input(:topic),
        suffix: context(:suffix)
      }
  end

  output from(:echo)
end

defmodule BaguTest.WorkflowCapability.FailingWorkflow do
  @moduledoc false

  use Bagu.Workflow

  workflow do
    id :workflow_capability_failure
    input Zoi.object(%{reason: Zoi.string()})
  end

  steps do
    tool :fail, BaguTest.WorkflowCapability.Fail, input: %{reason: input(:reason)}
  end

  output from(:fail)
end

defmodule BaguTest.WorkflowCapability.DuplicateNameTool do
  @moduledoc false

  use Bagu.Tool,
    name: "workflow_capability_math",
    description: "Conflicts with the default workflow capability name.",
    schema: Zoi.object(%{value: Zoi.integer()})

  @impl true
  def run(params, _context), do: {:ok, params}
end

defmodule BaguTest.WorkflowCapability.MathAgent do
  @moduledoc false

  use Bagu.Agent

  agent do
    id :workflow_capability_agent
  end

  defaults do
    instructions "Use deterministic workflows for known tasks."
  end

  capabilities do
    workflow(BaguTest.WorkflowCapability.MathWorkflow,
      as: :run_math,
      result: :structured
    )
  end
end

defmodule BaguTest.WorkflowCapability.ContextAgent do
  @moduledoc false

  use Bagu.Agent

  agent do
    id :workflow_context_capability_agent
  end

  defaults do
    instructions "Use deterministic workflows with forwarded context."
  end

  capabilities do
    workflow(BaguTest.WorkflowCapability.ContextWorkflow,
      as: :context_echo,
      forward_context: {:only, [:suffix]}
    )
  end
end

defmodule BaguTest.WorkflowCapability.FailingAgent do
  @moduledoc false

  use Bagu.Agent

  agent do
    id :workflow_failure_capability_agent
  end

  defaults do
    instructions "Expose a failing workflow for tests."
  end

  capabilities do
    workflow(BaguTest.WorkflowCapability.FailingWorkflow, as: :fail_workflow)
  end
end
