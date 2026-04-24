# Phoenix LiveView

Phoenix integration should treat Jidoka as an OTP runtime plus a projection
source. The LiveView should own UI state and rendering. The agent should own
execution. `Jido.Thread` should remain the canonical event log.

The important boundary is that the provider-facing LLM context is not the same
thing as the user-visible chat transcript.

## Why The Boundary Matters

An agent turn may include:

- user messages
- assistant messages
- assistant tool-call messages
- tool result messages
- context operations
- memory injection
- guardrail and hook metadata
- debug events

Only some of that belongs in a chat UI. Tool results, context operations, and
private reasoning metadata are useful for debugging, but they should not be
rendered as normal user-facing messages.

Jidoka exposes two layers for this split:

```elixir
{:ok, projection} = Jidoka.Agent.View.snapshot(pid)
{:ok, view} = MyAppWeb.SupportChatAgentView.snapshot(pid, session)

view.visible_messages
view.streaming_message
view.llm_context
view.events
```

`Jidoka.Agent.View` is the low-level projection from `Jido.Thread` and active
strategy state. `Jidoka.AgentView` is the least-common-denominator application
surface that adds agent selection, conversation ids, runtime context, optimistic
state, async request lifecycle, and result mapping.

## Dev Phoenix App

The local consumer app under `dev/jidoka_consumer` contains a minimal LiveView
spike.

Run it:

```bash
cd dev/jidoka_consumer
mix deps.get
mix phx.server
```

Then open http://localhost:4002.

The root LiveView renders four panels:

- visible messages
- turn summary
- run trace
- LLM context
- runtime context

The visible-message panel appends `streaming_message` while an async chat request
is running, then replaces it with the final thread-backed assistant message when
the request completes.

The source files are:

- `dev/jidoka_consumer/lib/jidoka_consumer_web/live/support_chat_live.ex`
- `dev/jidoka_consumer/lib/jidoka_consumer_web/live/support_chat_agent_view.ex`
- `lib/jidoka/agent_view.ex`
- `lib/jidoka/agent/view.ex`

The LiveView adapter starts
`JidokaConsumer.Support.Agents.SupportRouterAgent`, which belongs to the
consumer app and exposes the local ETS-backed `JidokaConsumer.Support.Ticket`
resource as ticket tools alongside local workflows, guardrails, specialist
subagents, and a billing handoff. The separate
`dev/jidoka_consumer/lib/jidoka_consumer/support_note_agent.ex` module remains
for focused Ash actor-passthrough tests, not for the chat UI.

## AgentView Pattern

The spike uses a rendering-free AgentView module:

```elixir
defmodule MyAppWeb.SupportChatAgentView do
  use Jidoka.AgentView,
    agent: MyApp.SupportAgent

  @impl true
  def conversation_id(session) do
    session
    |> Map.get("conversation_id", "demo")
    |> Jidoka.AgentView.normalize_id("demo")
  end

  @impl true
  def agent_id(session), do: "support-liveview-#{conversation_id(session)}"

  @impl true
  def runtime_context(session) do
    %{
      channel: "phoenix_live_view",
      session: conversation_id(session)
    }
  end
end
```

`use Jidoka.AgentView` generates the common operations:

- `start_agent/1`
- `snapshot/3`
- `before_turn/2`
- `start_turn/4`
- `await_turn/2`
- `refresh_turn/2`
- `after_turn/2`
- `visible_messages/1`

The AgentView owns the application surface:

- it chooses the agent
- it chooses the conversation id
- it builds runtime context
- it starts or reuses a runtime agent
- it projects the agent thread into UI data
- it defines lifecycle hooks around submit/result behavior

The AgentView should not mutate the thread directly and should not render HTML.
It should call Jidoka runtime APIs and then re-project the agent state.

## LiveView Flow

A LiveView can follow this shape:

```elixir
def mount(_params, session, socket) do
  {:ok, pid} = MyAppWeb.SupportChatAgentView.start_agent(session)
  {:ok, view} = MyAppWeb.SupportChatAgentView.snapshot(pid, session)

  {:ok,
  socket
   |> assign(:agent_pid, pid)
   |> assign(:session, session)
   |> assign(:view, view)
   |> assign(:message, "")
   |> assign(:active_request_id, nil)
   |> assign(:active_run, nil)}
end

def handle_event("send", %{"message" => message}, socket) do
  view = MyAppWeb.SupportChatAgentView.before_turn(socket.assigns.view, message)
  socket = assign(socket, view: view, message: "")

  {:ok, run} =
    MyAppWeb.SupportChatAgentView.start_turn(
      socket.assigns.agent_pid,
      message,
      socket.assigns.session
  )

  live_view = self()

  Task.Supervisor.start_child(MyApp.AgentViewTaskSupervisor, fn ->
    result = MyAppWeb.SupportChatAgentView.await_turn(run)
    send(live_view, {:chat_complete, run.request_id, result})
  end)

  {:noreply, assign(socket, active_request_id: run.request_id, active_run: run)}
end

def handle_info({:stream_tick, request_id}, socket) do
  {:ok, view} =
    MyAppWeb.SupportChatAgentView.refresh_turn(
      socket.assigns.active_run,
      socket.assigns.view
    )

  {:noreply, assign(socket, :view, view)}
end

def handle_info({:chat_complete, request_id, result}, socket) do
  {:ok, view} =
    MyAppWeb.SupportChatAgentView.after_turn(
      socket.assigns.active_run,
      result
    )

  {:noreply, assign(socket, active_request_id: nil, active_run: nil, view: view)}
end
```

This keeps optimistic UI behavior in LiveView and canonical message history in
the agent thread. The local consumer app also schedules a short recurring
`stream_tick` while `active_request_id` is set so provider deltas appear as a
normal LiveView update instead of a separate browser streaming channel.
`start_turn/4` returns a `%Jidoka.AgentView.Run{}` so refresh and completion use
the actual routed request server, including conversation handoff owners.

## Runtime Context

Build runtime context from trusted session/application data:

```elixir
context = %{
  actor: current_user,
  tenant: tenant,
  channel: "phoenix_live_view",
  session: conversation_id
}

Jidoka.chat(pid, message,
  conversation: conversation_id,
  context: context
)
```

Do not let the browser provide authorization context directly. Use browser
params for message text; use server-side session data for actor, tenant, and
permission scope.

## Debugging

Use both APIs:

```elixir
MyAppWeb.SupportChatAgentView.snapshot(pid, session)
Jidoka.Agent.View.snapshot(pid)
Jidoka.inspect_request(pid)
```

`SupportChatAgentView.snapshot/3` is the application surface. `Jidoka.Agent.View`
is the low-level projection. `Jidoka.inspect_request/1` is for request-level
diagnostics such as hooks, guardrails, memory, subagents, workflows, handoffs,
usage, and errors.

## Design Direction

The Jidoka-level abstraction is not a Phoenix-specific component. It is an
AgentView contract:

- core projection: project `Jido.Thread` into stable data shapes
- AgentView: define the agent, context, conversation id, and lifecycle hooks
- Phoenix: render the projected data and manage optimistic/pending state

That leaves Phoenix free to use LiveView idioms while keeping Jidoka's runtime
portable to controllers, channels, jobs, tests, or non-Phoenix UIs.
