# Examples

Jidoka includes examples under `examples/` and exposes them through `mix jidoka`.
Use dry-runs first to inspect the configuration without provider calls.

## Chat

```bash
mix jidoka chat --dry-run
mix jidoka chat -- "Use the add_numbers tool to add 17 and 25. Reply with only the sum."
```

Source:

- `examples/chat/agents/chat_agent.ex`
- `examples/chat/tools/add_numbers.ex`
- `examples/chat/hooks/*`
- `examples/chat/guardrails/*`
- `examples/chat/plugins/math_plugin.ex`

This is the best starting point for a single compiled agent with tools, hooks,
guardrails, plugins, and memory.

## Imported

```bash
mix jidoka imported --dry-run
mix jidoka imported -- "Use the add_numbers tool to add 17 and 25."
```

Source:

- `examples/chat/imported/sample_math_agent.json`
- `examples/chat/imported_demo.ex`

This shows the constrained JSON import path and explicit registries for runtime
resolution.

## Orchestrator

```bash
mix jidoka orchestrator --dry-run
mix jidoka orchestrator -- "Use the research_agent specialist to explain vector databases."
```

Source:

- `examples/orchestrator/agents/manager_agent.ex`
- `examples/orchestrator/agents/research_agent.ex`
- `examples/orchestrator/imported/sample_writer_specialist.json`

This demonstrates subagents: a manager delegates bounded work while keeping
control of the conversation.

## Workflow

```bash
mix jidoka workflow --dry-run
mix jidoka workflow
```

Source:

- `examples/workflow/workflows/math_pipeline.ex`
- `examples/workflow/tools/add_amount.ex`
- `examples/workflow/tools/double_value.ex`

This is the smallest deterministic workflow: add one, then double.

## Trace Smoke Test

```bash
mix jidoka trace
mix jidoka trace --log-level trace -- 7
```

This provider-free command verifies that Jidoka's structured trace collector is
attached, that Jido.AI telemetry is ingested, and that Jidoka workflow events
show up in `Jidoka.Trace`.

## Phoenix Support App

```bash
cd dev/jidoka_consumer
PORT=4002 mix phx.server
```

Source:

- `dev/jidoka_consumer/lib/jidoka_consumer/support/agents/support_router_agent.ex`
- `dev/jidoka_consumer/lib/jidoka_consumer/support/agents/billing_specialist_agent.ex`
- `dev/jidoka_consumer/lib/jidoka_consumer/support/agents/operations_specialist_agent.ex`
- `dev/jidoka_consumer/lib/jidoka_consumer/support/agents/writer_specialist_agent.ex`
- `dev/jidoka_consumer/lib/jidoka_consumer/support/workflows/refund_review.ex`
- `dev/jidoka_consumer/lib/jidoka_consumer/support/workflows/escalation_draft.ex`
- `dev/jidoka_consumer/lib/jidoka_consumer/support/ticket.ex`
- `dev/jidoka_consumer/lib/jidoka_consumer_web/live/support_chat_live.ex`

This is the decision fixture for Jidoka orchestration:

- chat agent owns open-ended intake
- Ash owns local ETS-backed ticket state
- subagents handle one-off specialist tasks
- workflows own fixed processes
- workflow capabilities let the agent choose a deterministic process
- handoffs transfer future turns in a conversation
- guardrails block unsafe input before model calls

## Kitchen Sink

```bash
mix jidoka kitchen_sink --dry-run --log-level trace
mix jidoka kitchen_sink -- "Use the research_agent specialist to explain embeddings."
```

Source:

- `examples/kitchen_sink/agents/kitchen_sink_agent.ex`
- `examples/kitchen_sink/README.md`

The kitchen sink combines schema, dynamic prompts, tools, Ash resource
expansion, skills, MCP sync, plugins, hooks, guardrails, memory, compiled
subagents, and imported subagents. It is a showcase, not the recommended first
copy/paste target.

## Turning Dry-Runs Into Live Sessions

Dry-runs do not start agents or execute workflows. Remove `--dry-run` and set a
provider key for live agent runs:

```bash
export ANTHROPIC_API_KEY=sk-ant-...
mix jidoka chat -- "Use one sentence to explain what Jidoka is."
```

Use `--log-level debug` for compact traces and `--log-level trace` for detailed
configuration and event output.

## Copying Patterns

Copy from examples by intent:

- need one agent with a tool: start from `examples/chat`
- need imported JSON: start from `examples/chat/imported`
- need manager delegation: start from `examples/orchestrator`
- need deterministic steps: start from `examples/workflow`
- need all orchestration boundaries: start from `dev/jidoka_consumer`

Avoid copying demo-only CLI wiring into application code. Keep application
agents under your app modules and call them through `Jidoka.start_agent/2`,
generated `start_link/1`, `Jidoka.chat/3`, and `Jidoka.Workflow.run/3`.
