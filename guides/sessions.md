# Sessions

`Jidoka.Session` is the canonical way to name an ongoing agent conversation.
It is a plain data descriptor, not a GenServer, transcript store, or persistence
layer. The running Jido agent process still owns runtime state, `Jido.Thread`
still owns conversation history, and `Jidoka.chat/3` still runs each turn.

Use a session when the same user, ticket, room, or workflow should keep talking
to the same logical agent over multiple turns.

## Build A Session

```elixir
session =
  Jidoka.Session.new!(
    agent: MyApp.SupportAgent,
    id: "support-123",
    context: %{tenant: "acme", actor: current_user}
  )
```

The session derives:

- `id`: normalized application session id
- `conversation_id`: defaults to `id`, used for handoff routing
- `agent_id`: stable runtime agent id for this session
- `context`: default runtime context merged into every turn
- `context_ref`: advanced Jido.AI projection lane, defaulting to `"default"`

## Chat With A Session

`Jidoka.chat/3` accepts a session directly:

```elixir
{:ok, reply} =
  Jidoka.chat(session, "Summarize this support ticket.")
```

This starts or reuses the session runtime agent, injects the session
conversation id and context, and then follows the normal chat lifecycle. Per-turn
context merges over the session context:

```elixir
Jidoka.chat(session, "Draft a reply.",
  context: %{ticket_id: ticket.id}
)
```

The async chat request helper also accepts sessions for non-blocking turns.

## Inspect A Session

Sessions work with the existing inspection and tracing helpers:

```elixir
{:ok, projection} = Jidoka.Session.snapshot(session)
{:ok, request} = Jidoka.inspect_request(session)
{:ok, trace} = Jidoka.inspect_trace(session)
```

`snapshot/2` projects the running agent with `Jidoka.Agent.View`. It does not
create a transcript; it reads from the runtime agent's thread.

## Sessions And AgentView

`Jidoka.AgentView` can use a session directly. When an AgentView has no
configured `agent:`, the default callbacks derive the agent, agent id,
conversation id, and runtime context from the session.

```elixir
defmodule MyAppWeb.SupportChatView do
  use Jidoka.AgentView
end

{:ok, pid} = MyAppWeb.SupportChatView.start_agent(session)
{:ok, view} = MyAppWeb.SupportChatView.snapshot(pid, session)
```

Override AgentView callbacks only when your UI boundary needs custom identity
or context rules.

## Sessions And Schedules

Schedules can target a session:

```elixir
{:ok, _schedule} =
  Jidoka.schedule(session,
    id: "support-123-check-in",
    cron: "0 9 * * *",
    prompt: "Check whether this ticket needs follow-up.",
    context: %{channel: "schedule"}
  )
```

When the schedule runs, Jidoka calls `Jidoka.chat(session, prompt, opts)`, so
hooks, guardrails, memory, structured output, handoffs, and tracing all behave
the same way as a normal turn.

## What Sessions Do Not Do

Sessions do not persist data by themselves. If the VM restarts, the running
agent process and its in-memory thread are gone unless your application uses
Jido persistence or a future Jidoka durability layer.

Your application still owns user identity, authorization, database schemas,
retention policy, and business metadata. Jidoka sessions only standardize the
addressing model used across chat, AgentView, schedules, handoffs, tracing, and
inspection.

## See Also

- [running-agents.md](running-agents.md): choosing runtime lifetimes.
- [agent-view.md](agent-view.md): projecting sessions for UI surfaces.
- [schedules.md](schedules.md): recurring session turns.
- [handoffs.md](handoffs.md): conversation ownership routing.
- [tracing.md](tracing.md): inspecting runtime execution.
