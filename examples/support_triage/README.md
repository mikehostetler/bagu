# Support Triage

Canonical support automation example:

- load a support ticket from a fixture-backed tool
- route it through deterministic business logic
- return a typed triage decision
- block obvious payment secrets before model execution

```bash
mix jidoka support_triage --dry-run --log-level trace
mix jidoka support_triage --verify
mix jidoka support_triage -- "Triage ticket TCK-1001."
```

The `--verify` command does not call a provider. It exercises the tools and the
same structured output finalization path used by live agent runs.
