# Examples

Jidoka includes examples under `examples/` and exposes them through `mix jidoka`.
Use dry-runs first to inspect the configuration without provider calls.

See [Mix Tasks](mix-tasks.html) for the canonical flag reference (`--dry-run`,
`--verify`, `--log-level`). Many of these examples also have notebook
equivalents under `livebook/`, indexed in [Livebooks](livebooks.html).

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

## Canonical Business Examples

These examples are meant to look like small real application agents. Agent code,
tools, fixtures, and demo wiring live under `examples/<name>/`; the library only
provides the generic demo loader.

### Support Triage

```bash
mix jidoka support_triage --dry-run --log-level trace
mix jidoka support_triage --verify
mix jidoka support_triage -- "Triage ticket TCK-1001."
```

Source:

- `examples/support_triage/agents/triage_agent.ex`
- `examples/support_triage/tools/load_ticket.ex`
- `examples/support_triage/tools/route_ticket.ex`
- `examples/support_triage/guardrails/block_payment_secrets.ex`

This shows a support agent that loads a ticket, routes it through deterministic
business logic, blocks obvious payment secrets, and returns typed triage output.

### Lead Qualification

```bash
mix jidoka lead_qualification --dry-run --log-level trace
mix jidoka lead_qualification --verify
mix jidoka lead_qualification -- "Qualify northwind.example."
```

Source:

- `examples/lead_qualification/agents/lead_agent.ex`
- `examples/lead_qualification/tools/enrich_company.ex`
- `examples/lead_qualification/tools/score_lead.ex`

This shows a sales agent that enriches a company, scores fit and intent, and
returns a CRM-ready structured output object.

### Data Analyst

```bash
mix jidoka data_analyst --dry-run --log-level trace
mix jidoka data_analyst --verify
mix jidoka data_analyst -- "How did core revenue change from February to March 2026?"
```

Source:

- `examples/data_analyst/agents/analyst_agent.ex`
- `examples/data_analyst/tools/query_revenue.ex`
- `examples/data_analyst/tools/compare_periods.ex`

This shows a data agent that queries fixture metrics, runs deterministic math,
and returns a typed analysis summary.

### Meeting Follow-Up

```bash
mix jidoka meeting_followup --dry-run --log-level trace
mix jidoka meeting_followup --verify
mix jidoka meeting_followup -- "Create follow-up for meeting CS-42."
```

This shows a meeting agent that extracts decisions, action items, risks, and
follow-up copy from fixture-backed notes.

### Customer Feedback Synthesizer

```bash
mix jidoka feedback_synthesizer --dry-run --log-level trace
mix jidoka feedback_synthesizer --verify
mix jidoka feedback_synthesizer -- "Synthesize feedback batch Q2-VOICE."
```

This shows a product feedback agent that groups comments into themes and returns
sentiment, risks, requests, and recommended actions.

### Invoice Extraction

```bash
mix jidoka invoice_extraction --dry-run --log-level trace
mix jidoka invoice_extraction --verify
mix jidoka invoice_extraction -- "Extract invoice INV-4432."
```

This shows a document extraction agent that validates structured invoice output
and includes an invalid-output edge case in verification.

### Incident Triage

```bash
mix jidoka incident_triage --dry-run --log-level trace
mix jidoka incident_triage --verify
mix jidoka incident_triage -- "Investigate alert ALERT-9."
```

This shows a workflow-as-tool agent that runs an ordered incident investigation
before returning an escalation plan.

### Approval Flow

```bash
mix jidoka approval_flow --dry-run --log-level trace
mix jidoka approval_flow --verify
mix jidoka approval_flow -- "Send a $750 refund for customer C-100."
```

This shows a risky tool protected by a tool guardrail that produces an approval
interrupt before execution.

### PR Reviewer

```bash
mix jidoka pr_reviewer --dry-run --log-level trace
mix jidoka pr_reviewer --verify
mix jidoka pr_reviewer -- "Review PR-17."
```

This shows a code review agent that loads a fixture diff and returns
severity-ranked findings plus test gaps.

### Research Brief

```bash
mix jidoka research_brief --dry-run --log-level trace
mix jidoka research_brief --verify
mix jidoka research_brief -- "Brief me on agent observability."
```

This shows a retrieval-style agent that ranks fixture sources and returns a
sourced brief.

### Document Intake

```bash
mix jidoka document_intake --dry-run --log-level trace
mix jidoka document_intake --verify
mix jidoka document_intake -- "Route document DOC-INV."
```

This shows a document intake agent that classifies mixed operational documents,
routes them, and returns normalized extracted fields.

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
expansion, skills, MCP sync, plugins, hooks, guardrails, memory, compaction,
compiled subagents, and imported subagents. It is a showcase, not the
recommended first copy/paste target.

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
- need a realistic support workflow: start from `examples/support_triage`
- need sales/CRM enrichment: start from `examples/lead_qualification`
- need fixture-backed data analysis: start from `examples/data_analyst`
- need meeting action items: start from `examples/meeting_followup`
- need product feedback synthesis: start from `examples/feedback_synthesizer`
- need document extraction: start from `examples/invoice_extraction`
- need incident workflows: start from `examples/incident_triage`
- need human approval interrupts: start from `examples/approval_flow`
- need code review output: start from `examples/pr_reviewer`
- need sourced briefs: start from `examples/research_brief`
- need document routing: start from `examples/document_intake`
- need imported JSON: start from `examples/chat/imported`
- need manager delegation: start from `examples/orchestrator`
- need deterministic steps: start from `examples/workflow`
- need all orchestration boundaries: start from `dev/jidoka_consumer`

Avoid copying demo-only CLI wiring into application code. Keep application
agents under your app modules and call them through `Jidoka.start_agent/2`,
generated `start_link/1`, `Jidoka.chat/3`, and `Jidoka.Workflow.run/3`.
