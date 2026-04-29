# Approval Flow

Canonical human approval example:

- expose a risky refund tool
- use a tool guardrail to interrupt before execution
- run the approved deterministic path
- return a structured approval summary

```bash
mix jidoka approval_flow --dry-run --log-level trace
mix jidoka approval_flow --verify
mix jidoka approval_flow -- "Send a $750 refund for customer C-100."
```
