# AgentView

`Jidoka.AgentView` is the adapter between an agent runtime and an application
surface. It is not a Phoenix view and it does not render HTML. Use it when an
agent backs a chat UI, controller, channel, CLI session, background job, or test
and you need one place to define conversation identity, runtime context, and
turn lifecycle.

If `Jidoka.chat/3` is enough for your caller, use it directly. Reach for
`AgentView` when the caller needs projected messages, async turns, streaming
drafts, or a stable application-facing shape.

When your surface already has a `%Jidoka.Session{}`, AgentView can use it
directly. Session inputs provide the agent, conversation id, runtime agent id,
and runtime context defaults without adding a separate session process.

## Two Projection Layers

Jidoka exposes two layers:

```elixir
{:ok, projection} = Jidoka.Agent.View.snapshot(pid)
{:ok, view} = MyAppWeb.SupportChatAgentView.snapshot(pid, session)
```

`Jidoka.Agent.View` is the low-level projection from `Jido.Thread` and active
strategy state. It is useful for debugging and raw runtime state.

`Jidoka.AgentView` adds application decisions:

- which agent module backs this surface
- how to derive the conversation id
- how to derive the runtime agent id
- how to build trusted runtime context
- how to start or reuse the agent
- how to represent visible messages and in-flight drafts
- how to map final results, interrupts, handoffs, and errors into view state

## Define An Adapter

The smallest adapter passes the backing agent:

```elixir
defmodule MyAppWeb.SupportChatAgentView do
  use Jidoka.AgentView,
    agent: MyApp.SupportAgent
end
```

If the caller passes a `%Jidoka.Session{}`, the adapter can be even smaller:

```elixir
defmodule MyAppWeb.SupportChatAgentView do
  use Jidoka.AgentView
end

session =
  Jidoka.Session.new!(
    agent: MyApp.SupportAgent,
    id: "support-123",
    context: %{actor: current_user}
  )
```

Most applications should override the identity and context callbacks:

```elixir
defmodule MyAppWeb.SupportChatAgentView do
  use Jidoka.AgentView,
    agent: MyApp.SupportAgent

  @impl true
  def conversation_id(session) do
    session
    |> Map.get("conversation_id", "support")
    |> Jidoka.AgentView.normalize_id("support")
  end

  @impl true
  def agent_id(session), do: "support-liveview-#{conversation_id(session)}"

  @impl true
  def runtime_context(session) do
    %{
      channel: "phoenix_live_view",
      session: conversation_id(session),
      actor: Map.fetch!(session, :current_user)
    }
  end
end
```

The generated helpers are:

- `start_agent/1`
- `snapshot/3`
- `before_turn/2`
- `start_turn/4`
- `await_turn/2`
- `refresh_turn/2`
- `after_turn/2`
- `visible_messages/1`
- `request_id/0`

## Turn Lifecycle

The common async flow is:

```elixir
{:ok, pid} = MyAppWeb.SupportChatAgentView.start_agent(session)
{:ok, view} = MyAppWeb.SupportChatAgentView.snapshot(pid, session)

view = MyAppWeb.SupportChatAgentView.before_turn(view, message)

{:ok, run} =
  MyAppWeb.SupportChatAgentView.start_turn(
    pid,
    message,
    session,
    timeout: 30_000
  )

{:ok, running_view} = MyAppWeb.SupportChatAgentView.refresh_turn(run, view)
result = MyAppWeb.SupportChatAgentView.await_turn(run)
{:ok, final_view} = MyAppWeb.SupportChatAgentView.after_turn(run, result)
```

`before_turn/2` applies optimistic state. `start_turn/4` creates an async Jido.AI
request and returns a `%Jidoka.AgentView.Run{}`. `refresh_turn/2` re-projects
state while the turn is still running. `after_turn/2` maps the public chat result
into final view state.

## View Data

An AgentView struct contains:

- `agent_id`
- `conversation_id`
- `runtime_context`
- `visible_messages`
- `streaming_message`
- `llm_context`
- `events`
- `status`
- `error`
- `error_text`
- `outcome`
- `metadata`

The important distinction is that `visible_messages` are safe for user-facing
transcripts, while `llm_context` is provider-facing context. They are related,
but they are not the same thing.

## Phoenix Pattern

In Phoenix LiveView, the socket process should not block on a model call. Use a
`Task.Supervisor` to await the turn and send the result back to the LiveView:

```elixir
live_view = self()

{:ok, _pid} =
  Task.Supervisor.start_child(MyApp.AgentViewTaskSupervisor, fn ->
    result = MyAppWeb.SupportChatAgentView.await_turn(run, timeout: 30_000)
    send(live_view, {:chat_complete, run.request_id, result})
  end)
```

The LiveView can poll `refresh_turn/2` or use normal LiveView messages to update
the projected streaming draft. See [Phoenix LiveView](phoenix-liveview.html) for
the full flow and the local `dev/jidoka_consumer` example.

## Outside Phoenix

`AgentView` is intentionally surface-neutral. You can use the same adapter from
a controller, channel, job, or CLI task:

```elixir
def run_support_turn(session, message) do
  with {:ok, pid} <- MyAppWeb.SupportChatAgentView.start_agent(session),
       {:ok, run} <- MyAppWeb.SupportChatAgentView.start_turn(pid, message, session),
       result <- MyAppWeb.SupportChatAgentView.await_turn(run),
       {:ok, view} <- MyAppWeb.SupportChatAgentView.after_turn(run, result) do
    {:ok, view}
  end
end
```

That keeps identity, context, visible transcript rules, and result mapping in
one adapter instead of scattering them across each interaction surface.

## Design Rules

- Put trusted context construction in the AgentView, not in browser params.
- Keep rendering out of the AgentView.
- Do not mutate `Jido.Thread` directly; call Jidoka runtime APIs and re-project.
- Use stable conversation ids for sessions and generated ids for one-off work.
- Use `Jidoka.Agent.View.snapshot/2` for low-level debugging, not as the main
  application surface.
