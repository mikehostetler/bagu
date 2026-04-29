# Research Brief

Canonical retrieval synthesis example:

- load fixture-backed source snippets
- rank source relevance
- produce a sourced brief with key points and open questions
- require at least one cited source in output

```bash
mix jidoka research_brief --dry-run --log-level trace
mix jidoka research_brief --verify
mix jidoka research_brief -- "Brief me on agent observability."
```
