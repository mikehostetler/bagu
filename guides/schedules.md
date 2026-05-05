# Schedules

Jidoka schedules run agents and workflows on cron without asking the application
to bring Oban, Quantum, or system cron for the common case. A schedule is still
an ordinary Jidoka turn: agent schedules call `Jidoka.chat/3`, and workflow
schedules call `Jidoka.Workflow.run/3`.

The beta schedule manager is in-memory. It is a good fit for app-local recurring
work, demos, internal agents, and development. Durable schedule persistence and
replay are planned as part of Jidoka's durability work.

## Programmatic Schedules

Register an agent schedule with a target, cron expression, prompt, and optional
context:

```elixir
{:ok, schedule} =
  Jidoka.schedule(MyApp.SupportDigestAgent,
    id: "daily-support-digest",
    cron: "0 9 * * *",
    timezone: "America/Chicago",
    prompt: "Prepare the daily support digest.",
    conversation: "support-digest",
    context: &MyApp.SupportDigest.context/0,
    overlap: :skip
  )
```

When the cron fires, the manager starts or reuses the target agent and runs:

```elixir
Jidoka.chat(pid, prompt,
  conversation: "support-digest",
  context: resolved_context,
  request_id: generated_request_id
)
```

When the target is an agent module, the default runtime agent id is the schedule
id. Pass `agent_id:` when the schedule should use an existing app-scoped agent.
When the target is a `%Jidoka.Session{}`, the schedule starts or reuses that
session's runtime agent and merges scheduled context over the session context:

```elixir
session =
  Jidoka.Session.new!(
    agent: MyApp.SupportDigestAgent,
    id: "support-digest",
    context: %{tenant: "acme"}
  )

{:ok, _schedule} =
  Jidoka.schedule(session,
    id: "daily-support-digest",
    cron: "0 9 * * *",
    prompt: "Prepare the daily support digest.",
    context: %{channel: "schedule"}
  )
```

That means schedules keep the same context validation, memory, compaction,
hooks, guardrails, structured output, handoffs, and tracing as a normal chat
turn.

## Workflow Schedules

Workflow schedules run deterministic workflows directly:

```elixir
{:ok, _schedule} =
  Jidoka.schedule_workflow(MyApp.DailyMetricsWorkflow,
    id: "daily-metrics",
    cron: "30 7 * * *",
    timezone: "Etc/UTC",
    input: %{window: "yesterday"},
    context: &MyApp.Metrics.runtime_context/0
  )
```

Use workflows for scheduled work that should be mostly deterministic and agents
for scheduled work that needs a model turn.

## Declared Agent Schedules

Agents can declare schedules for the application to register from its runtime
boundary:

```elixir
defmodule MyApp.SupportDigestAgent do
  use Jidoka.Agent

  agent do
    id :support_digest_agent
  end

  defaults do
    model :fast
    instructions "Prepare concise operational digests."
  end

  schedules do
    schedule :daily_digest do
      cron "0 9 * * *"
      timezone "America/Chicago"
      prompt "Prepare the daily support digest."
      context {MyApp.SupportDigest, :context, []}
      conversation "support-digest"
      overlap :skip
    end
  end
end
```

The generated agent exposes `schedules/0`:

```elixir
Enum.each(MyApp.SupportDigestAgent.schedules(), fn schedule ->
  {:ok, _schedule} = Jidoka.Schedule.Manager.put_schedule(schedule)
end)
```

Schedules are not registered automatically at compile time. Register them from
your application boundary so tests, releases, and supervision topology stay
explicit.

## Runtime Supervision

The Jidoka OTP application starts the default in-memory manager:

```elixir
Jidoka.Schedule.Manager
```

For an application-owned schedule manager, start it in your supervision tree:

```elixir
children = [
  {Jidoka.Schedule.Manager,
   name: MyApp.ScheduleManager,
   schedules: MyApp.SupportDigestAgent.schedules()}
]
```

Then pass the manager name to public APIs:

```elixir
Jidoka.list_schedules(manager: MyApp.ScheduleManager)
Jidoka.run_schedule("support_digest_agent:daily_digest", manager: MyApp.ScheduleManager)
Jidoka.cancel_schedule("support_digest_agent:daily_digest", manager: MyApp.ScheduleManager)
```

## Overlap

The default overlap policy is `:skip`. If a previous run is still executing when
the next cron tick fires, Jidoka records a skipped run and does not start another
turn.

Use `overlap: :allow` only when concurrent runs are safe.

## Manual Runs

You can trigger a schedule immediately:

```elixir
{:ok, run} = Jidoka.run_schedule("daily-support-digest")
```

The run record includes status, request id, timing, and the raw result for the
manual caller. Stored schedule history keeps bounded previews rather than full
raw results.

## Tracing

Schedules emit structured `:schedule` trace events for start, stop, error,
handoff, interrupt, and skip. For agent schedules, use the generated request id
from the run record:

```elixir
{:ok, run} = Jidoka.run_schedule("daily-support-digest")
{:ok, trace} = Jidoka.Trace.for_request("daily-support-digest", run.request_id)
```
