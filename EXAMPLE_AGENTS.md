# Example Agents

This file tracks the canonical example agents Jidoka should ship with. The
examples should feel like small real application agents, not synthetic API
snippets. Each one should demonstrate a practical automation pattern while
keeping agent-specific code under `examples/<slug>/`.

## Goals

- Show new users how Jidoka maps to common agent use cases.
- Keep examples working and testable in CI.
- Prefer deterministic provider-free verification through `--verify`.
- Keep reusable demo infrastructure in `lib/jidoka/demo/*`.
- Keep domain-specific agents, tools, fixtures, workflows, hooks, and guardrails
  under `examples/<slug>/`.

## Example Contract

Every canonical example should provide:

- `examples/<slug>/README.md`
- `examples/<slug>/demo.ex`
- one or more modules under `examples/<slug>/agents/`
- domain tools, workflows, guardrails, hooks, or fixtures in the same folder
- `mix jidoka <slug> --dry-run --log-level trace`
- `mix jidoka <slug> --verify`
- optional live mode: `mix jidoka <slug> -- "prompt..."`
- tests that prove discovery, dry-run output, and provider-free verification

Provider-free `--verify` should exercise the real Jidoka boundary where
possible: tools, workflows, guardrails, tracing, imported specs, structured
output finalization, or runtime inspection. Live provider calls are useful for
manual QA, but they should not be required for the default test suite.

## Current Examples

Verified on April 29, 2026:

| Example | Status | Verify Command | Coverage |
| --- | --- | --- | --- |
| Support Triage | Working | `mix jidoka support_triage --verify` | tools, guardrail, structured output |
| Lead Qualification | Working | `mix jidoka lead_qualification --verify` | tools, structured output |
| Data Analyst | Working | `mix jidoka data_analyst --verify` | tools, deterministic math, structured output |
| Meeting Follow-Up | Working | `mix jidoka meeting_followup --verify` | tools, output guardrail, structured output |
| Customer Feedback Synthesizer | Working | `mix jidoka feedback_synthesizer --verify` | batch tools, structured arrays |
| Invoice Extraction | Working | `mix jidoka invoice_extraction --verify` | extraction tools, validation failure |
| Incident Triage | Working | `mix jidoka incident_triage --verify` | workflow-as-tool, escalation output |
| Approval Flow | Working | `mix jidoka approval_flow --verify` | tool guardrail, interrupt, approval path |
| PR Reviewer | Working | `mix jidoka pr_reviewer --verify` | diff tools, review output guardrail |
| Research Brief | Working | `mix jidoka research_brief --verify` | retrieval tools, source guardrail |
| Document Intake Router | Working | `mix jidoka document_intake --verify` | classification, extraction, route tool |

### Support Triage

Status: verified working.

Path: `examples/support_triage`

Command:

```bash
mix jidoka support_triage --verify
```

Demonstrates:

- support ticket lookup
- deterministic routing tool
- input guardrail for payment secrets
- structured triage output

Good follow-up hardening:

- add a workflow-backed escalation path
- add a second specialist subagent for billing investigation
- add a negative verification case for the payment-secret guardrail

### Lead Qualification

Status: verified working.

Path: `examples/lead_qualification`

Command:

```bash
mix jidoka lead_qualification --verify
```

Demonstrates:

- company enrichment from fixtures
- lead scoring tool
- CRM-ready structured output

Good follow-up hardening:

- add deduplication or existing-account lookup
- add a follow-up email draft as a second output field
- add validation cases for unknown domains and low-fit leads

### Data Analyst

Status: verified working.

Path: `examples/data_analyst`

Command:

```bash
mix jidoka data_analyst --verify
```

Demonstrates:

- fixture-backed metric query
- deterministic period comparison
- typed analysis answer with caveats

Good follow-up hardening:

- add a small CSV fixture instead of embedded maps
- add a workflow for query, compare, explain
- add trace timeline output to the verify command

## Build Queue

| Order | Example | Slug | Status | Primary Jidoka Features |
| --- | --- | --- | --- | --- |
| 1 | Meeting Follow-Up | `meeting_followup` | verified working | structured output, fixture tools, output guardrail |
| 2 | Customer Feedback Synthesizer | `feedback_synthesizer` | verified working | batch tools, structured arrays, trace/debug |
| 3 | Invoice Extraction | `invoice_extraction` | verified working | structured output, validation failure, repair path |
| 4 | Incident Triage | `incident_triage` | verified working | workflow-as-tool, trace timeline, escalation |
| 5 | Approval Flow | `approval_flow` | verified working | tool guardrail, interrupt, approval context |
| 6 | PR Reviewer | `pr_reviewer` | verified working | code-review output, fixture diff tool, guardrail |
| 7 | Research Brief | `research_brief` | verified working | retrieval tools, source-aware output, web optionality |
| 8 | Document Intake Router | `document_intake` | verified working | classification, extraction, route tool |
| 9 | Team Orchestrator | `team_orchestrator` | later | subagents, imported agents, call graph |
| 10 | Durable Support Desk | `durable_support_desk` | blocked on durability | persistence, replay, handoffs |

## Implemented Agent Details

### Meeting Follow-Up

Proposed slug: `meeting_followup`

User story:

An operator pastes meeting notes. The agent extracts decisions, action items,
owners, due dates, risks, and drafts a short follow-up email.

Jidoka features to showcase:

- structured output
- fixture-backed note parser or tool
- optional output guardrail for unsupported commitments
- concise prompt/instructions

Provider-free verification:

- run a fixture transcript through local extraction logic
- finalize a representative structured model answer
- assert owners, action items, and follow-up draft fields

Suggested output fields:

- `summary`
- `decisions`
- `action_items`
- `risks`
- `follow_up_email`

### Customer Feedback Synthesizer

Proposed slug: `feedback_synthesizer`

User story:

A product team has a batch of customer comments. The agent groups comments into
themes, rates sentiment, identifies representative quotes, and recommends next
actions.

Jidoka features to showcase:

- batch fixture processing
- tools for loading comments and grouping signals
- structured output with arrays
- trace/debug output for multi-step reasoning support

Provider-free verification:

- load a fixed set of comments
- run deterministic theme grouping
- finalize a structured synthesis output
- assert expected themes and recommendation count

Suggested output fields:

- `themes`
- `sentiment`
- `top_requests`
- `risks`
- `recommended_actions`

### Invoice Extraction

Proposed slug: `invoice_extraction`

User story:

An operations user pastes invoice text. The agent extracts vendor, invoice
number, line items, due date, total, and validation warnings.

Jidoka features to showcase:

- structured output as the main value proposition
- validation failures and repair path
- deterministic parser tool for fixture text
- edge-case verification for malformed totals

Provider-free verification:

- parse fixture invoice text
- finalize a valid structured output
- finalize one invalid output and assert a normalized validation error

Suggested output fields:

- `vendor`
- `invoice_number`
- `issued_on`
- `due_on`
- `line_items`
- `total`
- `warnings`

### PR Review

Proposed slug: `pr_reviewer`

User story:

A developer provides a diff. The agent reviews it and returns findings ordered
by severity with file references and suggested fixes.

Jidoka features to showcase:

- code-review-shaped structured output
- fixture-backed diff loader
- guardrail against broad style-only findings
- possible subagent for security/performance review

Provider-free verification:

- load a known fixture diff
- run a deterministic smell detector for one issue
- finalize structured review findings
- assert severity, file, and line fields

Suggested output fields:

- `summary`
- `findings`
- `test_gaps`
- `recommended_next_steps`

### Incident Triage

Proposed slug: `incident_triage`

User story:

An on-call engineer submits an alert payload. The agent classifies severity,
checks recent metrics/log snippets, proposes likely causes, and produces a
response plan.

Jidoka features to showcase:

- deterministic workflow as an agent tool
- trace timeline for ordered investigation
- structured output
- interrupt or escalation when severity is high

Provider-free verification:

- run a workflow over alert, metric, and log fixtures
- assert both workflow steps run in order
- finalize incident summary output
- assert trace contains workflow events

Suggested output fields:

- `severity`
- `affected_service`
- `likely_causes`
- `recommended_actions`
- `escalate`

### Approval Flow

Proposed slug: `approval_flow`

User story:

An agent can prepare a risky action, but execution requires human approval. The
example should make interrupts feel intentional rather than exceptional.

Jidoka features to showcase:

- tool guardrail
- interrupt shape
- context forwarding to hooks
- structured result after approval path

Provider-free verification:

- call the risky tool through the guardrail path
- assert an interrupt is produced
- run an approved deterministic action path

Suggested output fields:

- `action`
- `risk_level`
- `approval_required`
- `approval_reason`
- `result`

### Research Brief

Proposed slug: `research_brief`

User story:

A user asks for a short brief on a topic. The agent gathers source snippets from
fixtures or optional web tools, ranks relevance, and writes a sourced summary.

Jidoka features to showcase:

- tool-backed retrieval
- optional web capability
- source-aware structured output
- guardrails around unsupported claims

Provider-free verification:

- load fixture source snippets
- rank snippets deterministically
- finalize a sourced brief output
- assert each claim has a source id

Suggested output fields:

- `brief`
- `key_points`
- `sources`
- `open_questions`

### Document Intake Router

Proposed slug: `document_intake`

User story:

An operations inbox receives mixed document-like text. The agent identifies the
document type, extracts a small normalized summary, and routes it to the right
queue.

Jidoka features to showcase:

- classification plus extraction
- imported agent spec parity candidate
- structured output
- route tool

Provider-free verification:

- run three fixtures: invoice, contract note, support request
- assert each routes to the expected queue
- assert output schema validation for each document type

Suggested output fields:

- `document_type`
- `route`
- `confidence`
- `summary`
- `extracted_fields`

## Advanced Showcase Examples

These are still useful, but they are better as later examples because they have
more moving parts.

### Team Orchestrator

Proposed slug: `team_orchestrator`

Purpose:

Show a manager agent coordinating multiple specialists, including at least one
compiled subagent and one imported JSON/YAML subagent.

Primary features:

- subagents
- imported agents
- context forwarding
- structured subagent result summaries
- trace/call graph inspection

### Durable Support Desk

Proposed slug: `durable_support_desk`

Purpose:

Show the eventual durability posture once persistence is first class. This
should wait until the durability gap is implemented.

Primary features:

- persistent conversation/request state
- replayable traces
- handoffs
- workflow history

## Build Order

1. Harden all verified examples with more negative verification cases.
2. Add trace timeline output to examples that exercise workflows and guardrails.
3. Revisit `team_orchestrator` after the smaller examples are stable.
4. Build `durable_support_desk` after first-class durability lands.

## Test Matrix

Each implemented example should appear in the mix task tests:

```bash
mix jidoka <slug> --dry-run --log-level trace
mix jidoka <slug> --verify
```

The package-level verification remains:

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix test
mix docs --warnings-as-errors
mix coveralls
```

Live provider smoke tests are manual and should be run when changing prompt or
tool behavior:

```bash
mix jidoka <slug> --log-level debug -- "example prompt"
```

## Definition Of Done

An example is done when:

- `mix jidoka <slug>` lists it in the command help
- `--dry-run --log-level trace` explains the compiled agent surface
- `--verify` runs without provider credentials
- tests cover discovery, dry-run, and verification
- README documents the scenario, commands, and what the example teaches
- no domain-specific code is added under `lib/`
