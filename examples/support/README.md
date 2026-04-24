# Support Demo Moved

The full-featured support demo now lives in the Phoenix consumer app:

```text
dev/jidoka_consumer/lib/jidoka_consumer/support
```

That app owns the support domain, including the ETS-backed Ash ticket resource,
router agent, specialist agents, workflows, guardrail, handoff, and LiveView
projection. Keeping it there avoids having two competing support
implementations in the repo.

Run it from the consumer app:

```bash
cd dev/jidoka_consumer
PORT=4002 mix phx.server
```
