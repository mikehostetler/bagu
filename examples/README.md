# Jidoka Examples

Examples are loaded by convention through `mix jidoka <name>`.

Each canonical example keeps agent-specific code inside its own folder and
supports provider-free verification:

```bash
mix jidoka support_triage --verify
mix jidoka lead_qualification --verify
mix jidoka data_analyst --verify
mix jidoka meeting_followup --verify
mix jidoka feedback_synthesizer --verify
mix jidoka invoice_extraction --verify
mix jidoka incident_triage --verify
mix jidoka approval_flow --verify
mix jidoka pr_reviewer --verify
mix jidoka research_brief --verify
mix jidoka document_intake --verify
```

Use `--dry-run --log-level trace` to inspect compiled agent configuration before
starting a live provider-backed run.
