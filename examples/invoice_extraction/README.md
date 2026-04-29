# Invoice Extraction

Canonical extraction example:

- load invoice text from fixtures
- parse normalized invoice fields
- validate structured output
- prove an invalid output edge case fails cleanly

```bash
mix jidoka invoice_extraction --dry-run --log-level trace
mix jidoka invoice_extraction --verify
mix jidoka invoice_extraction -- "Extract invoice INV-4432."
```
