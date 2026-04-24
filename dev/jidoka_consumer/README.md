# Jidoka Consumer

Small local integration harness for `jidoka` + `ash_jido` + Phoenix LiveView.

This consumer app exists to validate real Ash resource integration behavior
without coupling those checks to Jidoka's unit tests.

It currently verifies:

- AshJido actor passthrough from `scope` when `actor` is omitted
- authorization failure when neither `actor` nor `scope.actor` is present
- Jidoka's current `ash_resource` behavior: no default actor is supplied, and
  `Jidoka.Agent` requires an explicit `context.actor`
- a local ETS-backed support ticket resource exposed to a consumer-owned support
  router with workflows, guardrails, specialists, and handoffs
- Phoenix LiveView integration with a thread-backed Jidoka AgentView projection

## Phoenix LiveView Spike

The root LiveView demonstrates the proposed Jidoka/Phoenix boundary:

- `JidokaConsumerWeb.SupportChatAgentView` uses `Jidoka.AgentView` to
  start/reuse a Jidoka agent and define the UI-facing projection hooks.
- The view adapter runs
  `JidokaConsumer.Support.Agents.SupportRouterAgent`, a consumer app router over
  `JidokaConsumer.Support.Ticket`, so the Phoenix demo owns its resource,
  workflows, guardrails, specialist agents, and handoff boundary instead of
  loading packaged examples.
- `JidokaConsumer.Support.Ticket` uses `Ash.DataLayer.Ets` and exposes
  `create_support_ticket`, `list_support_tickets`, and `update_support_ticket`
  through AshJido.
- `Jidoka.Agent.View` projects the canonical `Jido.Thread` into separate
  `visible_messages`, in-flight `streaming_message`, `llm_context`, and debug
  `events`.
- `JidokaConsumerWeb.SupportChatLive` renders those projections without treating
  the visible transcript as the provider-facing LLM context.
- Chat submits start async Jido.AI requests; the LiveView polls the projected
  streaming assistant draft while the request runs, then replaces it with the
  final thread-backed assistant message.

Run the Phoenix server:

```bash
mix deps.get
mix phx.server
```

Then open http://localhost:4002.

## Run

```bash
cd dev/jidoka_consumer
mix setup
mix test
```
