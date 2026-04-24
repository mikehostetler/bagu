# Subagents, Workflows, And Handoffs

Jidoka has three orchestration primitives. They are intentionally separate because
they solve different problems.

## Decision Table

| Need | Use | Why |
| --- | --- | --- |
| Ask a specialist during one chat turn | `subagent` | Parent agent stays in control. |
| Run a known ordered process | `workflow` | Application owns the steps and dependencies. |
| Transfer future turns to another agent | `handoff` | Conversation ownership changes. |

## Subagents

A subagent is an agent exposed as a tool:

```elixir
capabilities do
  subagent MyApp.ResearchAgent,
    as: :research_agent,
    description: "Ask the research specialist for concise notes.",
    target: :ephemeral,
    forward_context: {:only, [:tenant, :session]},
    result: :structured
end
```

Use this when the parent can ask for a bounded result and then decide how to
reply. Examples:

- "Ask the research specialist for background."
- "Ask the billing specialist to summarize this invoice."
- "Ask the writer specialist to rewrite this paragraph."

The parent model still controls the final answer.

## Workflows

A workflow is deterministic application logic:

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

Run it directly:

```elixir
{:ok, output} =
  Jidoka.Workflow.run(MyApp.Workflows.RefundReview, %{
    account_id: "acct_123",
    order_id: "ord_456",
    reason: "Damaged on arrival"
  })
```

Expose it to an agent:

```elixir
capabilities do
  workflow MyApp.Workflows.RefundReview,
    as: :review_refund,
    description: "Review refund eligibility for a known account and order.",
    result: :structured
end
```

Use workflows when the order matters and application code should own the
process, not the model.

## Workflows Can Use Agents

Workflows can include bounded agent steps:

```elixir
steps do
  function :prompt, {MyApp.WorkflowFns, :build_prompt, 2},
    input: %{issue: input(:issue)}

  agent :draft, MyApp.WriterAgent,
    prompt: from(:prompt, :prompt),
    context: %{account_id: input(:account_id)}
end
```

This keeps the boundary explicit: the workflow owns the sequence; the agent owns
one bounded language task.

## Handoffs

A handoff transfers ownership for future turns in a `conversation:`:

```elixir
capabilities do
  handoff MyApp.BillingAgent,
    as: :transfer_billing_ownership,
    description: "Transfer ongoing billing ownership to billing.",
    target: :auto,
    forward_context: {:only, [:tenant, :session, :account_id]}
end
```

Call chat with a conversation id:

```elixir
{:handoff, handoff} =
  Jidoka.chat(router_pid, "Billing should own this from here.",
    conversation: "support-123",
    context: %{tenant: "acme", account_id: "acct_123"}
  )
```

Future calls with the same conversation route to the owner:

```elixir
Jidoka.chat(router_pid, "What is the next billing step?",
  conversation: "support-123"
)
```

Inspect and reset ownership:

```elixir
Jidoka.handoff_owner("support-123")
Jidoka.reset_handoff("support-123")
```

## Consumer Support Boundary

The Phoenix consumer support app demonstrates all three primitives:

- `billing_specialist`, `operations_specialist`, and `writer_specialist` are
  subagents for one-off specialist work.
- `review_refund` exposes a deterministic refund workflow to the router agent.
- `transfer_billing_ownership` hands future billing turns to billing.
- `escalation_draft` is a workflow that uses `writer_specialist` as one bounded
  step.

Run the app:

```bash
cd dev/jidoka_consumer
PORT=4002 mix phx.server
```

## Practical Rule

If the model should decide "who can help me answer this?", use a subagent.

If the app already knows the steps, use a workflow.

If the user should keep talking to a different agent after this turn, use a
handoff.
