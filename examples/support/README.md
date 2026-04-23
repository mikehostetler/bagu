# Bagu Support Example

This example is for teasing apart the current Bagu boundary between chat agents
and workflows.

It intentionally keeps both surfaces visible:

- a front-door support chat agent with a team of specialist subagents and one
  deterministic workflow capability
- explicit workflows for fixed support processes

The current example keeps the boundaries explicit:

- chat agent owns open-ended intake and delegation
- workflows own deterministic support processes
- the chat agent can expose a workflow as a tool-like capability
- workflows can reuse a specialist agent as one bounded step
- guardrails own hard safety boundaries before the agent calls a model or
  specialist

## Team

The front-door `support_router_agent` can delegate to:

- `review_refund`, a deterministic workflow capability for known refund cases
- `billing_specialist`
- `operations_specialist`
- `writer_specialist`

It also installs the `support_sensitive_data` input guardrail. Requests that try
to reveal payment credentials, secrets, or bypass verification are rejected
before the LLM or any specialist subagent is called.

## Workflows

- `refund_review`
  - tool-only
  - loads customer + order data
  - applies deterministic refund policy
  - returns a structured decision
  - is exposed to the router as `review_refund`

- `escalation_draft`
  - deterministic process
  - classifies severity and queue
  - uses `writer_specialist` as a bounded drafting step
  - returns a structured escalation package

## Run It

Dry-run:

```bash
mix bagu support --log-level trace --dry-run
```

Chat path:

```bash
mix bagu support -- "Customer acct_vip says order ord_damaged arrived broken and wants a refund because it was damaged on arrival."
```

Workflow path:

```bash
mix bagu support -- "/refund acct_vip ord_damaged Damaged on arrival"
mix bagu support -- "/escalate acct_trial Customer is locked out and threatening to cancel"
```
