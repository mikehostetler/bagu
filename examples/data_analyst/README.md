# Data Analyst

Canonical data agent example:

- query local fixture metrics through tools
- compare periods with deterministic math
- return a typed analysis summary

```bash
mix jidoka data_analyst --dry-run --log-level trace
mix jidoka data_analyst --verify
mix jidoka data_analyst -- "How did core revenue change from February to March 2026?"
```

The `--verify` command proves the tool path and output contract without a
provider key.
