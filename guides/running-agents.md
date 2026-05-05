# Running Agents

After you define an agent, the next question is where it should live in your
application. Jidoka agents are ordinary OTP processes started under the shared
`Jidoka.Runtime` supervisor. Your application decides when to start them, which
ids they use, and how request or session context is passed to each turn.

Use this guide when you are wiring Jidoka into Phoenix, background jobs, CLI
tasks, tests, or any long-running OTP application.

## The Runtime Boundary

Compiled agents expose `start_link/1`, but that helper starts the runtime agent
under `Jidoka.Runtime`, which is itself a Jido instance:

```elixir
{:ok, pid} = MyApp.SupportAgent.start_link(id: "support-router")
```

The facade does the same thing:

```elixir
{:ok, pid} = Jidoka.start_agent(MyApp.SupportAgent.runtime_module(), id: "support-router")
```

You can then discover and stop agents by id:

```elixir
pid = Jidoka.whereis("support-router")
Jidoka.list_agents()
Jidoka.stop_agent("support-router")
```

Use stable ids for agents that should survive across requests or sessions. Use
generated ids for request-scoped workers.

This default runtime is the easy onramp. It gives new applications one shared
registry, task supervisor, agent supervisor, trace collector, and lookup surface
without asking you to design runtime topology first.

When you need runtime topology, Jido is already available underneath. Jido's
recommended pattern is to define an application-owned instance with
`use Jido, otp_app: :my_app`, add that instance to your supervision tree, and
start agents through the instance:

```elixir
defmodule MyApp.AgentRuntime do
  use Jido, otp_app: :my_app
end
```

```elixir
def start(_type, _args) do
  children = [
    MyApp.AgentRuntime,
    MyAppWeb.Endpoint
  ]

  Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)
end
```

Jidoka compiled agents expose `runtime_module/0` for exactly this bridge:

```elixir
{:ok, pid} =
  MyApp.AgentRuntime.start_agent(
    MyApp.SupportAgent.runtime_module(),
    id: "support-router"
  )

{:ok, reply} =
  Jidoka.chat(pid, "Triage this support ticket.",
    conversation: "support-123",
    context: %{session: "support-123", actor: current_user}
  )
```

Use a custom Jido instance when you need separate registries, task supervisors,
agent supervisors, scheduler configuration, debug settings, worker pools,
partitions, or persistence policies. Stay on `Jidoka.Runtime` when you just need
to run agents and chat with them. The underlying Jido docs call this an
instance module; see
[Jido Configuration](https://hexdocs.pm/jido/configuration.html) and
[Jido Runtime Patterns](https://hexdocs.pm/jido/runtime-patterns.html) when you
need to design that topology directly.

## Choose A Lifetime

| Lifetime | Use When | Shape |
| --- | --- | --- |
| Request-scoped | One HTTP request, one job, one CLI command | Start, chat, stop in the caller. |
| Session-scoped | One LiveView/browser session or support conversation | Derive a stable conversation id and agent id. |
| App-scoped | Shared router, analyst, or operations agent | Start once during application startup. |
| Scheduled | Recurring app-local work | `Jidoka.Schedule.Manager` triggers a normal agent turn or workflow run. |
| External job-triggered | Durable queues or external schedulers | External job triggers a turn on an agent or workflow. |

The main decision is not technical. It is ownership: does the agent represent a
single interaction, a user conversation, or an application-level worker?

## Request-Scoped

Request-scoped agents are the simplest operational shape. Start the agent near
the call site, pass trusted context, and stop it when the work is complete.

```elixir
def classify_ticket(ticket, current_user) do
  id = "ticket-classifier-#{System.unique_integer([:positive])}"

  try do
    with {:ok, pid} <- MyApp.TicketClassifier.start_link(id: id),
         {:ok, result} <-
           MyApp.TicketClassifier.chat(pid, ticket.body,
             context: %{actor: current_user, ticket_id: ticket.id},
             timeout: 30_000
           ) do
      {:ok, result}
    end
  after
    Jidoka.stop_agent(id)
  end
end
```

Use this when the agent does not need conversation memory or state between calls.

## Session-Scoped

Session-scoped agents work well for chat UIs and support conversations. Use
`Jidoka.Session` to keep the conversation id, runtime agent id, and trusted
runtime context in one plain descriptor. Derive the session id from server-side
data, not from untrusted browser params.

```elixir
session =
  Jidoka.Session.new!(
    agent: MyApp.SupportAgent,
    id: session["conversation_id"],
    context: %{actor: current_user}
  )

{:ok, reply} =
  Jidoka.chat(session, message)
```

The session is not a process or database record. It is an addressing model over
the running Jido agent process and its `Jido.Thread`. For UI-facing chat, pair a
session with `AgentView` so projected messages and async turn state have one
surface-neutral shape. See [Sessions](sessions.html) and [AgentView](agent-view.html).

Session-scoped agents are also the natural place to enable
[Compaction](compaction.html). The compaction snapshot lives on the running
agent state, while the full `Jido.Thread` remains available to AgentView and
inspection.

## App-Scoped

For long-lived agents, start them from your application startup flow after the
Jidoka application has started. A small bootstrapper process keeps the Phoenix
supervision tree honest without pretending the generated agent module owns the
process directly.

```elixir
defmodule MyApp.AgentBootstrapper do
  use GenServer

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @impl true
  def init(state) do
    {:ok, _pid} = MyApp.SupportRouterAgent.start_link(id: "support-router")
    {:ok, _pid} = MyApp.AnalystAgent.start_link(id: "analyst")

    {:ok, state}
  end
end
```

In a Phoenix app:

```elixir
def start(_type, _args) do
  children = [
    {Task.Supervisor, name: MyApp.AgentTaskSupervisor},
    MyApp.AgentBootstrapper,
    MyAppWeb.Endpoint
  ]

  Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)
end
```

The agents themselves are supervised by `Jidoka.Runtime`; the bootstrapper is
the application-owned place where you declare which long-lived agents should
exist.

If you already know the app needs an application-owned Jido instance, start the
same Jidoka agent through that instance instead:

```elixir
def init(state) do
  {:ok, _pid} =
    MyApp.AgentRuntime.start_agent(
      MyApp.SupportRouterAgent.runtime_module(),
      id: "support-router"
    )

  {:ok, state}
end
```

## Phoenix LiveView

For LiveView, use this split:

- Phoenix owns rendering, socket assigns, browser events, and optimistic UI.
- `Jidoka.AgentView` owns conversation id, agent id, runtime context, and turn
  lifecycle.
- The agent owns execution and the canonical thread.

The local consumer app follows this shape:

```elixir
children = [
  {Task.Supervisor, name: JidokaConsumer.AgentViewTaskSupervisor},
  {Phoenix.PubSub, name: JidokaConsumer.PubSub},
  JidokaConsumerWeb.Endpoint
]
```

The LiveView starts or reuses a per-session agent in `mount/3`, starts each turn
without blocking the socket process, and awaits completion in the task
supervisor. See [AgentView](agent-view.html) and
[Phoenix LiveView](phoenix-liveview.html).

## Scheduled Tasks

Use `Jidoka.Schedule.Manager` when the application needs recurring app-local
agent turns or workflow runs. The manager is supervised by Jidoka and keeps
scheduled execution on the same runtime path as ordinary calls.

```elixir
{:ok, _schedule} =
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

When the cron fires, Jidoka resolves the agent, then calls `Jidoka.chat/3` with
the configured prompt, context, conversation, and generated request id. That
means scheduled turns still run through context schemas, memory, hooks,
guardrails, compaction, structured output, and tracing.

For deterministic scheduled work, schedule a workflow:

```elixir
{:ok, _schedule} =
  Jidoka.schedule_workflow(MyApp.DailyMetricsWorkflow,
    id: "daily-metrics",
    cron: "30 7 * * *",
    input: %{window: "yesterday"},
    context: &MyApp.Metrics.context/0
  )
```

Agents can also declare schedules and let the application register them from
its runtime boundary:

```elixir
Enum.each(MyApp.SupportDigestAgent.schedules(), fn schedule ->
  {:ok, _schedule} = Jidoka.Schedule.Manager.put_schedule(schedule)
end)
```

See [Schedules](schedules.html) for schedule options, manual runs, overlap
policy, and trace inspection.

## External Background Jobs

Use Oban, system cron, or another external scheduler when you need durable job
queues, retries, uniqueness, backoff, or operational tooling beyond Jidoka's
in-memory beta scheduler. The job can start or look up an agent and run a normal
turn:

```elixir
defmodule MyApp.Workers.SupportDigest do
  use Oban.Worker, queue: :agents

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"account_id" => account_id}}) do
    {:ok, pid} = ensure_agent("support-digest-#{account_id}")

    Jidoka.chat(pid, "Prepare the daily support digest.",
      conversation: "support-digest-#{account_id}",
      context: %{account_id: account_id, channel: "oban"}
    )
  end

  defp ensure_agent(id) do
    case Jidoka.whereis(id) do
      nil -> MyApp.SupportDigestAgent.start_link(id: id)
      pid -> {:ok, pid}
    end
  end
end
```

This keeps durable scheduling, retries, uniqueness, and backoff in the job
system while Jidoka still owns the agent turn.

## When To Graduate Into Jido

Jidoka is meant to be an onramp. Keep using Jidoka for the agent DSL, structured
output, tools, workflows, AgentView, and `Jidoka.chat/3`. Add a custom Jido
instance when runtime topology becomes important. Move individual agents to
native Jido only when you need lower-level signals, directives, child lifecycle,
sensors, scheduler primitives, pools, pods, durable keyed lifecycle, or
fine-grained persistence.

See [Graduating To Jido](graduating-to-jido.html) for the step-by-step path.
