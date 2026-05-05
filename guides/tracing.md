# Tracing

`Jidoka.Trace` is first-class run trace data, sitting alongside structured
[errors](errors.md) and [inspection](inspection.md). A trace is a bounded,
in-memory projection of Jido and Jido.AI telemetry, enriched with
Jidoka-specific lifecycle events for hooks, guardrails, memory, compaction,
workflows, subagents, handoffs, MCP, and structured output.

Tracing is always on for running Jidoka agents. There is no `start/0` to call
and no collector to install: a trace accumulates automatically as a request
runs and is retrieved by agent target or `request_id`.

## Minimal example

Run a chat turn, then read the trace it produced:

```elixir
{:ok, pid} = MyApp.SupportAgent.start_link()
{:ok, _turn} = Jidoka.chat(pid, "Refund order 42, please.")

{:ok, trace}  = Jidoka.Trace.latest(pid)
{:ok, events} = Jidoka.Trace.events(trace)
{:ok, spans}  = Jidoka.Trace.spans(trace)
```

You can target a specific request when you have its id (for example, from a
[chat turn](chat-turn.md) result or from `Jidoka.inspect_request/1`):

```elixir
{:ok, trace} = Jidoka.Trace.for_request(pid, "req-abc123")
```

To list retained traces for a running agent:

```elixir
{:ok, traces} = Jidoka.Trace.list(pid, limit: 10)
```

All four functions accept a running PID, a registered Jidoka agent id, or a
`%Jido.Agent{}` snapshot. They return `{:ok, value}` or
`{:error, reason}` in the standard [error shapes](errors.md).

## The trace struct

`Jidoka.Trace` is a struct with stable, public fields:

- `:trace_id`: stable id for the trace
- `:run_id`: id for the agent run that produced it
- `:request_id`: id for the originating request
- `:agent_id`: the Jidoka agent id
- `:status`: terminal status, when set
- `:started_at_ms` / `:completed_at_ms`: monotonic timing in ms
- `:events`: ordered list of `%Jidoka.Trace.Event{}`
- `:summary`: rolled-up, source-tagged counters and totals

## Event shape

`Jidoka.Trace.Event` is the normalized projection of a single telemetry event.
Stable fields:

- `:seq`: monotonic per-trace sequence number
- `:at_ms`: event timestamp in ms
- `:source`: origin tag (for example, `:jido`, `:jido_ai`, `:jidoka`)
- `:category`: lifecycle category (for example, `:chat`, `:tool`, `:hook`,
  `:guardrail`, `:memory`, `:workflow`, `:subagent`, `:handoff`, `:mcp`,
  `:structured_output`, `:compaction`)
- `:event`: specific event atom within the category
- `:phase`: `:start`, `:stop`, or a category-specific phase
- `:name`: human-readable label, when available
- `:status`: `:completed`, `:failed`, `:cancelled`, `:interrupted`, or `nil`
- `:duration_ms`: span duration when known
- `:request_id`, `:run_id`, `:trace_id`: correlation ids
- `:span_id`, `:parent_span_id`: span correlation when available
- `:measurements`: telemetry measurement map
- `:metadata`: telemetry metadata map

`Jidoka.Trace.spans/2` derives coarse spans by grouping events by
`(category, correlation id)` and reports `started_at_ms`, `completed_at_ms`,
`duration_ms`, terminal `:status`, and `event_count` per span.

## Livebook helpers

`Jidoka.Kino` provides three trace renderers that work with any trace target:

- `Jidoka.Kino.timeline/2`: a compact, time-ordered table of events
- `Jidoka.Kino.trace_table/2`: a denser event table with category and metadata
- `Jidoka.Kino.call_graph/2`: a Mermaid call graph derived from spans
- `Jidoka.Kino.compaction/2`: the latest compaction snapshot as a small table

Each accepts a `%Jidoka.Trace{}`, a PID, an agent id, or a `%Jido.Agent{}`,
plus an optional `request_id:` to target a specific request:

```elixir
Jidoka.Kino.timeline(pid)
Jidoka.Kino.trace_table(pid, request_id: "req-abc123")
Jidoka.Kino.call_graph(trace)
Jidoka.Kino.compaction(pid)
```

For ad-hoc, log-based capture around a single block of code, use
`Jidoka.Kino.trace/3`, which captures runtime logs while the function runs and
renders them as a small table. It is independent of `Jidoka.Trace` and is
mostly useful for notebook exploration.

## Tracing vs inspection

Tracing and inspection are complementary:

- Tracing: an event stream over the whole run, including spans, retries, and
  lifecycle hooks. Use `Jidoka.Trace.events/2` or `Jidoka.Trace.spans/2` when
  you need to see how the run unfolded.
- Inspection: a stable snapshot of the most recent request or the agent
  definition. Use `Jidoka.inspect_request/1` or `Jidoka.inspect_agent/1` when
  you need a high-level summary right now.

In practice, `inspect_request/1` answers "what happened on the last call?",
while `Jidoka.Trace` answers "show me every step in order." See
[inspection.md](inspection.md) for the snapshot API.

## Using traces in tests and evals

Traces are convenient assertions targets in tests and [evals](evals.md):

```elixir
{:ok, _turn}   = Jidoka.chat(pid, "Refund order 42.")
{:ok, events}  = Jidoka.Trace.events(pid)

assert Enum.any?(events, fn e ->
         e.category == :tool and e.event == :call and e.status == :completed
       end)
```

Group on `:request_id` for multi-turn assertions, or on `:category` for
capability-level checks (tools, guardrails, MCP, and so on).

## See also

- [inspection.md](inspection.md)
- [errors.md](errors.md)
- [chat-turn.md](chat-turn.md)
- [evals.md](evals.md)
- [livebooks.md](livebooks.md)
- [imported-agents.md](imported-agents.md)

## Imported agents

Tracing applies identically to [imported agents](imported-agents.md): they go
through the same Jidoka runtime, emit the same lifecycle events, and are
queried with the same `Jidoka.Trace` and `Jidoka.Kino` functions. There is no
separate trace surface for the imported authoring path.
