# Production

Jidoka is beta software, and its runtime model is designed for ordinary OTP
applications. This guide collects the operational decisions to make before
shipping.

## Supervision

Jidoka starts a shared runtime from its OTP application. In an application that
depends on Jidoka, compiled agents are started under that shared
`Jidoka.Runtime` supervisor. Your application still owns the operational policy:
which agents should exist, what ids they use, and when request or session agents
should be stopped.

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

In Phoenix, the usual shape is:

```elixir
children = [
  {Task.Supervisor, name: MyApp.AgentTaskSupervisor},
  MyApp.AgentBootstrapper,
  MyAppWeb.Endpoint
]
```

Use the bootstrapper for app-scoped agents, `AgentView` for session-scoped UI
agents, `Jidoka.Schedule.Manager` for app-local recurring work, and durable job
workers when you need queue semantics. See [Running Agents](running-agents.html),
[Schedules](schedules.html), and [AgentView](agent-view.html) before copying
the LiveView-specific example.

If the application needs its own Jido instance for isolated registries, task
supervisors, scheduler configuration, pools, or persistence policy, see
[Graduating To Jido](graduating-to-jido.html).

## Provider Configuration

Set provider credentials through environment variables or runtime config, and
declare model aliases under `config :jidoka, :model_aliases`. See
[Models](models.html) and the README "Install and configure" section for the
canonical setup.

## Error Boundaries

At HTTP, CLI, job, and test boundaries, handle all four public return shapes
(`{:ok, _}`, `{:interrupt, _}`, `{:handoff, _}`, `{:error, _}`) and call
`Jidoka.format_error/1` for user-facing strings. See [Errors](errors.html).

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

## Imported Agents

The production checklist applies identically to imported JSON/YAML agents.
The hardening posture is the `available_*` registries: imported specs must
resolve executable pieces through explicit allowlists.

```elixir
Jidoka.import_agent_file(path,
  available_tools: [MyApp.Tools.LookupOrder],
  available_workflows: [MyApp.Workflows.RefundReview],
  available_handoffs: [MyApp.BillingAgent]
)
```

Do not let user-authored JSON/YAML select arbitrary modules. Keep raw module
strings invalid. See [Imported Agents](imported-agents.html).

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

## Context Compaction

Compaction is opt-in and summary-only in this beta. It is useful for
long-running sessions because it trims provider-facing history while preserving
the original in-memory `Jido.Thread`.

Before production, decide:

- which session-scoped agents need compaction
- whether the default prompt preserves the facts your domain needs
- how `max_messages`, `keep_last`, and `max_summary_chars` should be tuned
- whether summaries need durable storage outside the running agent process

Compaction failures fail open, emit trace metadata, and continue without
trimming. See [Compaction](compaction.html).

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

Use [Inspection](inspection.html) for stable views of agents, requests, and
workflows. Use [Tracing](tracing.html) for structured run traces through
`Jidoka.Trace`. Log request ids, agent ids, workflow ids, tool names, and
formatted Jidoka errors.

## Dependency Posture

The current beta candidate still uses pre-release ecosystem dependencies. The
package pins those Git dependencies by commit ref so consuming apps do not track
moving branches by accident.

Before a public Hex beta release, replace remaining local development-only paths
such as test fixtures with Hex releases, Git refs, or pinned tags. Keep the
public Jidoka API documented in these guides rather than relying on upstream
internals.

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
- review compaction thresholds and summary prompt
- review handoff persistence expectations
