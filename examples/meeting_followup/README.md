# Meeting Follow-Up

Canonical meeting automation example:

- load meeting notes from fixtures
- extract action items
- return decisions, risks, and a follow-up email as structured output
- block unsupported commitments in the generated follow-up copy

```bash
mix jidoka meeting_followup --dry-run --log-level trace
mix jidoka meeting_followup --verify
mix jidoka meeting_followup -- "Create follow-up for meeting CS-42."
```
