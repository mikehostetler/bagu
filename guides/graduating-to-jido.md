# Graduating To Jido

Jidoka is an onramp to the Jido ecosystem. Start here when you want a smaller
agent authoring surface: `use Jidoka.Agent`, `chat/3`, tools, workflows,
structured output, AgentView, and direct examples.

You do not need to leave Jidoka to ship useful agents. Graduate into Jido when
your runtime needs become more important than the simplified authoring surface.

## The Relationship

Jidoka is not a second runtime. A compiled Jidoka agent generates a Jido/Jido.AI
runtime module and starts it under `Jidoka.Runtime` by default.

```elixir
{:ok, pid} = MyApp.SupportAgent.start_link(id: "support-router")
```

That is equivalent to starting the generated runtime module under Jidoka's
default Jido instance:

```elixir
{:ok, pid} =
  Jidoka.Runtime.start_agent(
    MyApp.SupportAgent.runtime_module(),
    id: "support-router"
  )
```

This means the first graduation step is not a rewrite. It is usually just a
runtime ownership change.

## Stay With Jidoka When

- your application wants chat-oriented agents
- `Jidoka.chat/3` is the right turn API
- Zoi structured output is the main response contract
- tools and workflows cover deterministic application work
- subagents and handoffs cover orchestration
- AgentView gives your UI/API/job boundary enough structure
- one shared runtime is operationally sufficient

This is the expected path for most beta applications.

## Add A Custom Jido Instance When

Use Jido directly for runtime ownership when you need:

- an application-owned OTP instance in your supervision tree
- separate registries or task supervisors by app area
- separate runtime configuration per tenant or domain
- instance-level debug and observability controls
- worker pools for throughput-sensitive agents
- partitions for namespacing
- direct access to Jido's scheduler, runtime store, or persistence options

Define a Jido instance in your application:

```elixir
defmodule MyApp.Jido do
  use Jido, otp_app: :my_app
end
```

Add it to your supervision tree:

```elixir
def start(_type, _args) do
  children = [
    MyApp.Jido,
    MyAppWeb.Endpoint
  ]

  Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)
end
```

Then start the generated Jidoka runtime module through that instance:

```elixir
{:ok, pid} =
  MyApp.Jido.start_agent(
    MyApp.SupportAgent.runtime_module(),
    id: "support-router"
  )

{:ok, reply} =
  Jidoka.chat(pid, "Triage this ticket.",
    conversation: "support-123",
    context: %{session: "support-123", actor: current_user}
  )
```

You still get the Jidoka authoring surface, but the process belongs to your
application's Jido instance.

## Move One Agent At A Time

Use a staged migration:

1. Keep the Jidoka agent definition.
2. Start it through an application-owned Jido instance with `runtime_module/0`.
3. Keep calling `Jidoka.chat/3` while you validate the new runtime topology.
4. Move runtime-sensitive code, debug controls, scheduler work, or pools to the
   Jido instance.
5. Rewrite an individual agent as native `use Jido.Agent` only when the Jidoka
   DSL becomes the limiting factor.

This keeps Jidoka as the onramp and avoids a forced rewrite.

## Graduate Fully When

Native Jido is the better fit when you need to design the agent around:

- custom signal routes
- directive-heavy orchestration
- parent-child agent lifecycle inside a live workflow
- sensors
- Jido scheduler and cron primitives
- durable keyed lifecycle through Jido's instance-management tools
- worker pools and pods
- direct AgentServer `call/3` and `cast/2`
- storage, thaw/hibernate, or persistence primitives
- fine-grained instance-level telemetry and debug controls

At that point, write the agent directly in Jido and keep Jidoka around for
simpler agents that still benefit from the smaller DSL.

## Keep The Boundary Stable

Do not expose the migration to every caller. Keep a small application boundary:

```elixir
defmodule MyApp.Agents do
  def start_support_router do
    MyApp.Jido.start_agent(MyApp.SupportAgent.runtime_module(), id: "support-router")
  end

  def chat_support(message, opts) do
    with pid when is_pid(pid) <- MyApp.Jido.whereis("support-router") do
      Jidoka.chat(pid, message, opts)
    else
      nil -> {:error, :support_router_not_started}
    end
  end
end
```

Callers should not care whether the backing agent is a Jidoka-authored runtime
module or a native Jido agent. That boundary is what lets you graduate
incrementally.

## Jido References

The upstream docs to read next:

- [Jido Runtime Patterns](https://hexdocs.pm/jido/runtime-patterns.html)
- [Jido Runtime](https://hexdocs.pm/jido/runtime.html)
- [Jido Configuration](https://hexdocs.pm/jido/configuration.html)
- [Jido module API](https://hexdocs.pm/jido/Jido.html)

