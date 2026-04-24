# Production

Jidoka is pre-beta, but its runtime model is designed for ordinary OTP
applications. This guide collects the operational decisions to make before
shipping.

## Supervision

Jidoka starts a shared runtime from its OTP application. In an application that
depends on Jidoka, start compiled agents under your own supervision tree when they
should be long-lived, or start them on demand when they are request scoped.

Manual start:

```elixir
{:ok, pid} = MyApp.SupportAgent.start_link(id: "support-router")
```

Facade start:

```elixir
{:ok, pid} = Jidoka.start_agent(MyApp.SupportAgent.runtime_module(), id: "support-router")
```

Lookup:

```elixir
Jidoka.whereis("support-router")
Jidoka.list_agents()
```

Stop:

```elixir
Jidoka.stop_agent("support-router")
```

Choose stable ids for long-lived agents. Use generated or request-scoped ids for
temporary workers.

## Provider Configuration

Configure provider credentials through environment variables or runtime config.
In this repo, `.env` is loaded by `dotenvy`, and `ANTHROPIC_API_KEY` is used by
the examples.

Use model aliases for application defaults:

```elixir
config :jidoka, :model_aliases,
  fast: "anthropic:claude-haiku-4-5"
```

Then reference aliases in agents:

```elixir
defaults do
  model :fast
  instructions "You help support users."
end
```

## Error Boundaries

At HTTP, CLI, job, and test boundaries, handle all public return shapes:

```elixir
case Jidoka.chat(pid, message, context: context, conversation: conversation_id) do
  {:ok, reply} ->
    {:ok, reply}

  {:interrupt, interrupt} ->
    {:interrupt, interrupt}

  {:handoff, handoff} ->
    {:handoff, handoff}

  {:error, reason} ->
    {:error, Jidoka.format_error(reason)}
end
```

Keep raw `reason.details.cause` for logs and observability. Do not expose it
directly to end users unless your application sanitizes it.

## Context Security

Treat `context:` as privileged application data. The model can influence tool
arguments, but it should not be trusted to supply authorization context.

Good context values:

- current actor
- tenant
- account id
- session id
- request id
- permission scope

Do not forward secrets to subagents, workflows, or handoffs. Use
`forward_context: {:only, keys}` for most production delegation.

## Imported Spec Safety

Imported agents must resolve executable pieces through registries:

```elixir
Jidoka.import_agent_file(path,
  available_tools: [MyApp.Tools.LookupOrder],
  available_workflows: [MyApp.Workflows.RefundReview],
  available_handoffs: [MyApp.BillingAgent]
)
```

Do not let user-authored JSON/YAML select arbitrary modules. Keep raw module
strings invalid.

## Memory Storage

Memory is opt-in and backed by `jido_memory`. Retrieval failures are hard
errors; capture/write failures are soft warnings.

Before production, decide:

- which agents need memory
- how memory is partitioned
- whether namespace keys are stable and non-sensitive
- how long records should live
- how memory capture is audited

Use tools or databases for authoritative facts. Use memory for conversational
continuity.

## Handoff Registry

Handoffs currently use an in-memory registry for `conversation_id => owner`.
That is suitable for an MVP or single-node beta, but not durable cross-node
ownership.

Before relying on handoffs in production, decide how ownership should persist
across:

- node restarts
- deployments
- distributed nodes
- tenant boundaries
- manual resets

The public helpers are:

```elixir
Jidoka.handoff_owner("support-123")
Jidoka.reset_handoff("support-123")
```

## Observability

Use Jidoka inspection APIs in debug tooling:

```elixir
Jidoka.inspect_agent(MyApp.SupportAgent)
Jidoka.inspect_agent(pid)
Jidoka.inspect_request(pid)
Jidoka.inspect_workflow(MyApp.Workflows.RefundReview)
```

Use package demos and the Phoenix consumer app when learning behavior:

```bash
mix jidoka orchestrator --log-level trace --dry-run
cd dev/jidoka_consumer && PORT=4002 mix phx.server
```

For application observability, log request ids, agent ids, workflow ids, tool
names, and formatted Jidoka errors.

## Dependency Posture

The current beta candidate still uses local or pre-release ecosystem
dependencies in development, including `jido_runic` and `jido_eval` in this
monorepo.

Before a public Hex beta release, replace local paths with Hex releases, Git
refs, or pinned tags. Keep the public Jidoka API documented in these guides rather
than relying on upstream internals.

## Release Checklist

Before shipping a Jidoka-based application:

- run `mix test`
- run `mix quality`
- run relevant live evals with provider keys
- dry-run the example or app-specific CLI paths
- verify docs with `mix docs`
- review context forwarding policies
- review imported-agent registries
- review memory namespaces
- review handoff persistence expectations
