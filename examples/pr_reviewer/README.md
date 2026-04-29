# PR Reviewer

Canonical engineering review example:

- load a fixture diff
- detect a deterministic correctness issue
- return findings, test gaps, and recommended next steps as structured output
- block style-only review summaries

```bash
mix jidoka pr_reviewer --dry-run --log-level trace
mix jidoka pr_reviewer --verify
mix jidoka pr_reviewer -- "Review PR-17."
```
