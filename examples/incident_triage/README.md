# Incident Triage

Canonical incident response example:

- expose a deterministic investigation workflow as an agent tool
- classify an alert
- load service context
- build a response plan with escalation status

```bash
mix jidoka incident_triage --dry-run --log-level trace
mix jidoka incident_triage --verify
mix jidoka incident_triage -- "Investigate alert ALERT-9."
```
