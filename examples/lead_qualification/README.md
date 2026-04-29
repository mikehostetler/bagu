# Lead Qualification

Canonical sales automation example:

- enrich a lead from a fixture-backed company lookup
- score company fit and buying intent
- return a CRM-ready structured output object

```bash
mix jidoka lead_qualification --dry-run --log-level trace
mix jidoka lead_qualification --verify
mix jidoka lead_qualification -- "Qualify northwind.example."
```

The `--verify` command runs locally and proves the tools plus structured output
contract without calling a provider.
