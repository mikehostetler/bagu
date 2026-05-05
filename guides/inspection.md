# Inspection

Jidoka exposes inspection functions for getting structured visibility into
agents, requests, workflows, and context compaction: `Jidoka.inspect_agent/1`,
`Jidoka.inspect_request/1`, `Jidoka.inspect_workflow/1`, and
`Jidoka.inspect_compaction/1`. Each returns `{:ok, value}` with a stable,
documented field set, or `{:error, reason}` in the normalized
[error shapes](errors.md).

## Minimal example

```elixir
{:ok, definition} = Jidoka.inspect_agent(MyApp.SupportAgent)
{:ok, summary}    = Jidoka.inspect_request(pid)
{:ok, workflow}   = Jidoka.inspect_workflow(MyApp.Workflows.RefundReview)
{:ok, compacted}  = Jidoka.inspect_compaction(pid)
```

## Inspect agents

`Jidoka.inspect_agent/1` accepts a compiled agent module, an imported agent
struct, a running PID, or a registered server id. Compiled and imported
definitions return the same field set:

- `:kind`
- `:id`
- `:description`
- `:model`
- `:context`
- `:tool_names`
- `:subagent_names`
- `:workflow_names`
- `:handoff_names`
- `:memory`
- `:compaction`
- `:hooks`
- `:guardrails`

```elixir
{:ok, definition}          = Jidoka.inspect_agent(MyApp.SupportAgent)
{:ok, imported_definition} = Jidoka.inspect_agent(imported_agent)
{:ok, running}             = Jidoka.inspect_agent(pid)
```

Running agents return a `:running_agent` summary with the live `id`, the
underlying runtime and owner modules, the compiled `definition`, the
`request_count`, and the `last_request` summary (same shape as
`inspect_request/1`).

The DSL surface that produces these definitions is documented in
[agents.md](agents.md).

> Internal generated helpers on agent modules are not the public inspection
> API. Always go through `Jidoka.inspect_agent/1`.

## Inspect requests

`Jidoka.inspect_request/1` returns a structured summary for the most recent
request on a server. Pass a request id to target a specific one:

```elixir
{:ok, summary} = Jidoka.inspect_request(pid)
{:ok, summary} = Jidoka.inspect_request(pid, "req-123")
```

Stable fields include:

- `:request_id`, `:status`, `:duration_ms`
- `:model`, `:system_prompt`, `:message_count`
- `:input_message`, `:user_message`, `:context_preview`
- `:skills`, `:tool_names`, `:mcp_tools`, `:mcp_errors`
- `:memory`, `:compaction`, `:subagents`, `:workflows`, `:handoffs`
- `:usage`, `:interrupt`, `:error`

Subagent, workflow, handoff, guardrail, hook, memory, and compaction entries
are present when those features were involved in the turn. The capabilities
used by an agent emit bounded metadata via `result: :structured` so request
summaries stay safe to log.

## Inspect compaction

`Jidoka.inspect_compaction/1` returns the latest `%Jidoka.Compaction{}` snapshot
for a session, pid, registered agent id, or `%Jido.Agent{}` snapshot:

```elixir
{:ok, compaction} = Jidoka.inspect_compaction(session)
```

Use it to see whether the last evaluation was `:summarized`, `:skipped`, or
`:error`, plus bounded counts and summary preview. The full original thread is
still inspected through AgentView or request snapshots.

For time-series telemetry data across many requests, see
[tracing.md](tracing.md). For the normalized failure shape under `:error`,
see [errors.md](errors.md).

## Inspect workflows

`Jidoka.inspect_workflow/1` returns a compiled workflow definition with
stable fields:

- `:kind`
- `:id`
- `:module`
- `:description`
- `:input_schema`
- `:steps`
- `:dependencies`
- `:output`

```elixir
{:ok, workflow} = Jidoka.inspect_workflow(MyApp.Workflows.RefundReview)
```

Raw Runic graph structures are intentionally not part of this stable shape.

## Debug returns

For workflows, pass `return: :debug` to get a richer return value alongside
the normal output:

```elixir
{:ok, debug} =
  Jidoka.Workflow.run(MyApp.Workflows.RefundReview, input, return: :debug)
```

Workflow capabilities and subagents exposed to an agent can also surface
bounded metadata with `result: :structured`, which is what powers the
`:subagents` and `:workflows` entries in `inspect_request/1` summaries.

Use debug returns for observability and tests. Avoid requiring production
callers to pattern-match on internal causes unless they own that boundary.

## See also

- [errors.md](errors.md): normalized failure shapes returned alongside these
  inspection calls.
- [tracing.md](tracing.md): time-series run data and telemetry.
- [compaction.md](compaction.md): summary snapshots and provider-facing trim.
- [agents.md](agents.md): the DSL surface that produces compiled definitions.
- [chat-turn.md](chat-turn.md): the lifecycle that populates request
  summaries.

## Imported agents

`Jidoka.inspect_agent/1` accepts an imported agent value directly and returns
the same field set as a compiled agent definition. Request and workflow
inspection are identical: imported agents reach the same runtime. See
[imported-agents.md](imported-agents.md).
