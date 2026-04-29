# Workflows

A Jidoka workflow is deterministic application logic. The application owns the
sequence of steps and the data flowing between them, not the model. Define one
with `use Jidoka.Workflow`, run it directly, or expose it to an agent as a
tool-like capability.

Use a workflow when the order matters and you want application code, not an
LLM, to decide what runs next. For LLM-driven delegation use a
[subagent](subagents.md). For conversation ownership transfer use a
[handoff](handoffs.md).

## Minimal Example

```elixir
defmodule MyApp.Workflows.RefundReview do
  use Jidoka.Workflow

  workflow do
    id :refund_review
    description "Review refund eligibility."

    input Zoi.object(%{
      account_id: Zoi.string(),
      order_id: Zoi.string(),
      reason: Zoi.string()
    })
  end

  steps do
    tool :customer, MyApp.Tools.LoadCustomerProfile,
      input: %{account_id: input(:account_id)}

    tool :order, MyApp.Tools.LoadOrder,
      input: %{account_id: input(:account_id), order_id: input(:order_id)}

    function :decision, {MyApp.SupportFns, :finalize_refund_decision, 2},
      input: %{
        customer: from(:customer),
        order: from(:order),
        reason: input(:reason)
      }
  end

  output from(:decision)
end
```

## DSL Sections

`workflow do` configures the immutable contract:

- `id`: stable lower snake case workflow id.
- `description`: optional human-readable description.
- `input`: required Zoi object/map schema for workflow input.

`steps do` declares step entities. Three kinds are supported:

- `tool :name, ToolModule, input: %{...}`: run a `Jidoka.Tool` or generic Jido
  Action-backed module.
- `function :name, {Module, :fun, 2}, input: %{...}`: run a deterministic
  `fun.(params, context)`.
- `agent :name, AgentModule, prompt: ..., context: %{...}`: call a compiled
  Jidoka agent module, or `{:imported, key}` to call a runtime-provided
  imported agent.

Every step also accepts `after: [:other_step]` for control-only dependencies.

`output from(:step)` (or `output from(:step, :field)`) selects the workflow's
final value.

## Refs

Step `input:` and `agent` `prompt:`/`context:` mappings use ref helpers from
`Jidoka.Workflow.Ref`, which the DSL imports automatically:

- `input(:key)`: read a top-level workflow input field.
- `from(:step)`: read the full output of a prior step.
- `from(:step, :field)`: read a single field from a prior step.
- `context(:key)`: read a runtime side-band context value.
- `value(term)`: mark a static value explicitly.

## Running A Workflow

```elixir
{:ok, output} =
  Jidoka.Workflow.run(MyApp.Workflows.RefundReview, %{
    account_id: "acct_123",
    order_id: "ord_456",
    reason: "Damaged on arrival"
  })
```

`Jidoka.Workflow.run/3` accepts:

- `context:` map of side-band values for `context(:key)` refs.
- `agents:` map of imported agent values for `agent :name, {:imported, key}`
  steps.
- `timeout:` runtime timeout in milliseconds. Defaults to `30_000`.
- `return:` `:output` (default) or `:debug` to return the full step trace
  alongside the output.

For `:debug` runs, see [inspection.md](inspection.md).

## Agent Steps

A workflow can include a bounded agent call inside an otherwise deterministic
sequence:

```elixir
steps do
  function :prompt, {MyApp.WorkflowFns, :build_prompt, 2},
    input: %{issue: input(:issue)}

  agent :draft, MyApp.WriterAgent,
    prompt: from(:prompt, :prompt),
    context: %{account_id: input(:account_id)}
end
```

The workflow owns the sequence; the agent owns one bounded language task.

## Exposing A Workflow To An Agent

Once defined, a workflow can be surfaced to an agent as a tool-like capability:

```elixir
capabilities do
  workflow MyApp.Workflows.RefundReview,
    as: :review_refund,
    description: "Review refund eligibility for a known account and order.",
    result: :structured
end
```

`result:` defaults to `:output` (the raw workflow output). Use `:structured`
when the parent model should receive the workflow output as a structured tool
result.

## See Also

- [subagents.md](subagents.md): LLM-driven specialist delegation.
- [handoffs.md](handoffs.md): conversation ownership transfer.
- [tools.md](tools.md): Jidoka tool authoring and `Jidoka.Tool`.
- [inspection.md](inspection.md): `Jidoka.inspect_workflow/1` and debug runs.
- [structured-output.md](structured-output.md): structured workflow results.

## Imported Agents

Imported agents can declare a `workflows` capability that resolves a workflow
id through `available_workflows:`:

```elixir
Jidoka.import_agent(json,
  available_workflows: [MyApp.Workflows.RefundReview]
)
```

The imported spec references the workflow's published id, not an Elixir module
string. Workflow modules themselves are not imported: they are always compiled
Elixir defined with `use Jidoka.Workflow`. See
[imported-agents.md](imported-agents.md) for the workflow capability spec.
