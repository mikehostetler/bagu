# Document Intake

Canonical document routing example:

- load mixed document fixtures
- classify document type
- route to the right operational queue
- return normalized extracted fields

```bash
mix jidoka document_intake --dry-run --log-level trace
mix jidoka document_intake --verify
mix jidoka document_intake -- "Route document DOC-INV."
```
