# Feedback Synthesizer

Canonical product feedback example:

- load a batch of customer comments
- group comments into themes
- return sentiment, risks, requests, and product actions as structured output

```bash
mix jidoka feedback_synthesizer --dry-run --log-level trace
mix jidoka feedback_synthesizer --verify
mix jidoka feedback_synthesizer -- "Synthesize feedback batch Q2-VOICE."
```
