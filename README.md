# Jidoka

The easy on-ramp to LLM agents in Elixir.

Jidoka is a small, opinionated harness over [Jido](https://github.com/agentjido/jido)
and [Jido.AI](https://github.com/agentjido/jido_ai). It gives you a developer-friendly
DSL focused on the common LLM-agent use cases, without asking you to learn signals,
directives, state operations, strategy internals, or request plumbing on day one.

If you have looked at the broader Jido ecosystem and felt it was a lot to absorb
just to ship one agent, Jidoka is for you.

## Why this exists

The Jido ecosystem is powerful, but powerful is not the same as approachable.
Jidoka is the opinionated layer that:

- starts with a single agent module and a `chat/3` call
- grows progressively when you actually need tools, memory, structured output,
  workflows, subagents, or handoffs
- hides Jido's lower-level surface until you choose to opt in

You can stay on the easy path indefinitely, or drop down into Jido directly when
your application needs it. Jidoka does not get in the way.

## What you get

- **A tiny DSL.** `use Jidoka.Agent`, name it, give it instructions, you have an
  agent.
- **Fast time-to-first-agent.** Define, start, and chat in under thirty lines.
- **Progressive opt-in.** Tools, structured output, memory, characters,
  workflows, subagents, handoffs, MCP, web access, plugins, hooks, and
  guardrails are all available, but none are required.

## Your first agent

```elixir
defmodule MyApp.AssistantAgent do
  use Jidoka.Agent

  agent do
    id :assistant_agent
  end

  defaults do
    model :fast
    instructions "You are a concise assistant. Answer directly."
  end
end
```

Start it and chat:

```elixir
{:ok, pid} = MyApp.AssistantAgent.start_link(id: "assistant-1")

{:ok, reply} =
  MyApp.AssistantAgent.chat(pid, "Write one sentence about why Elixir works well for agents.")
```

That is a complete Jidoka agent. Only `agent.id` and `defaults.instructions`
are required. Everything else is optional.

You can also load the same conceptual agent from a JSON or YAML spec at
runtime. See [Two equal authoring paths](#two-equal-authoring-paths) below.

## Return structured data, not just text

For classification, extraction, and routing tasks, put the response shape on
the agent. Jidoka asks the model for JSON, parses it, validates it with
[Zoi](https://github.com/marpo60/zoi), and hands you back a typed map.

```elixir
defmodule MyApp.TicketClassifier do
  use Jidoka.Agent

  agent do
    id :ticket_classifier

    output do
      schema Zoi.object(%{
        category: Zoi.enum([:billing, :technical, :account]),
        confidence: Zoi.float(),
        summary: Zoi.string()
      })
    end
  end

  defaults do
    model :fast
    instructions "Classify support tickets for routing."
  end
end
```

```elixir
{:ok, pid} = MyApp.TicketClassifier.start_link(id: "ticket-classifier-1")

{:ok, ticket} =
  MyApp.TicketClassifier.chat(pid, "I was double charged for my last invoice.")

# ticket =>
# %{category: :billing, confidence: 0.92, summary: "Customer reports a duplicate invoice charge."}
```

Validation retries and repair behavior are configurable. See
[Structured Output](guides/structured-output.md) and [Errors](guides/errors.md)
for the details.

## Add a tool

Tools are how an agent does deterministic application work: lookups, math,
API calls, anything that should not be the model's job to imagine.

```elixir
defmodule MyApp.Tools.AddNumbers do
  use Jidoka.Tool,
    description: "Adds two integers.",
    schema: Zoi.object(%{a: Zoi.integer(), b: Zoi.integer()})

  @impl true
  def run(%{a: a, b: b}, _context) do
    {:ok, %{sum: a + b}}
  end
end

defmodule MyApp.MathAgent do
  use Jidoka.Agent

  agent do
    id :math_agent
  end

  defaults do
    model :fast
    instructions "Use tools when they help. Keep the final answer short."
  end

  capabilities do
    tool MyApp.Tools.AddNumbers
  end
end
```

The model can now call `add_numbers` mid-turn. See [Tools](guides/tools.md) for
the full tool API, plus the per-capability guides for
[Ash Resources](guides/ash-resources.md), [MCP](guides/mcp-tools.md),
[Web Access](guides/web-access.md), [Skills](guides/skills.md), and
[Plugins](guides/plugins.md).

## What else is in the box

Jidoka grows with you. The capabilities below are all optional and individually
documented under `guides/`.

### Agent building blocks

- **[Context schemas](guides/context.md)**: declare a Zoi schema on
  the agent and have per-turn `context:` validated before the model is called.
- **[Memory](guides/memory.md)**: opt-in conversation memory built on
  `jido_memory`, with simple namespace and capture/retrieve options.
- **[Characters](guides/characters.md)**: structured persona data for voice,
  tone, and identity, rendered into the prompt before instructions.
- **[Structured output](guides/structured-output.md)**: Zoi-validated final
  answers with retries and optional repair.

### Orchestration

- **[Workflows](guides/workflows.md)**: deterministic, app-owned multi-step
  processes via `use Jidoka.Workflow`.
- **[Subagents](guides/subagents.md)**: specialist agents exposed to a parent
  agent as tools, for one-turn delegation.
- **[Handoffs](guides/handoffs.md)**: transfer ownership of future turns in a
  conversation to another agent.

### Integrations and extensions

- **[Imported agents](guides/imported-agents.md)**: load agents from JSON or
  YAML at runtime through explicit allowlist registries.
- **MCP tools**: sync external tools through `jido_mcp`.
- **Web access**: constrained, read-only public web search and page reads.
- **Plugins**: deeper extension points that contribute tools and runtime
  behavior.
- **Ash resources**: expose generated `AshJido` actions as model-callable
  tools.

### Safety and runtime controls

- **Hooks and guardrails**: turn-scoped callbacks and input/output/tool
  validation.
- **Structured errors**: `Jidoka.format_error/1` turns any runtime failure
  into a user-safe string. See [Errors](guides/errors.md).
- **Inspection**: `Jidoka.inspect_agent/1`, `Jidoka.inspect_request/1`, and
  `Jidoka.inspect_workflow/1` expose stable views of definitions and runs.
- **Tracing**: first-class run traces through `Jidoka.Trace` and Livebook
  helpers.

### Where to learn each feature

Recommended reading order:

1. [Getting Started](guides/getting-started.md)
2. [Agents](guides/agents.md)
3. [Models](guides/models.md)
4. [Instructions](guides/instructions.md)
5. [Context](guides/context.md)
6. [Structured Output](guides/structured-output.md)
7. [Tools](guides/tools.md) (then see Capabilities for the rest)
8. [Subagents](guides/subagents.md), [Workflows](guides/workflows.md), [Handoffs](guides/handoffs.md)
9. [Memory](guides/memory.md)
10. [Imported Agents](guides/imported-agents.md)
11. [Errors](guides/errors.md) and [Inspection](guides/inspection.md)
12. [Examples](guides/examples.md)
13. [Phoenix LiveView](guides/phoenix-liveview.md)
14. [Production](guides/production.md)

The full guide index is at [guides/overview.md](guides/overview.md).

## Two equal authoring paths

Jidoka has two ways to describe the same conceptual agent. They are peers, not
a primary and a fallback.

### Elixir DSL

`use Jidoka.Agent` is the recommended path for Elixir developers. You get
compile-time validation, formatter support, and source-aware errors.

```elixir
defmodule MyApp.AssistantAgent do
  use Jidoka.Agent

  agent do
    id :assistant_agent
  end

  defaults do
    model :fast
    instructions "You are a concise assistant."
  end
end
```

### Imported JSON/YAML agents

For teams that want portable specs, or want to author agents without writing
Elixir, Jidoka supports a constrained runtime import path:

```elixir
json = ~S"""
{
  "agent": { "id": "json_agent" },
  "defaults": {
    "model": "fast",
    "instructions": "You are a concise assistant."
  }
}
"""

{:ok, agent} = Jidoka.import_agent(json)
{:ok, pid}   = Jidoka.start_agent(agent, id: "json-agent")
{:ok, reply} = Jidoka.chat(pid, "Say hello.")
```

YAML works the same way with `format: :yaml`. Tools, plugins, hooks,
guardrails, characters, workflows, and handoffs are resolved through explicit
`available_*` allowlist registries so imported agents stay safe.

See [Imported Agents](guides/imported-agents.md) for the full constrained
schema.

## Install and configure

### Add the dependency

Jidoka is alpha and not on Hex yet. Pin a commit ref from Git:

```elixir
def deps do
  [
    {:jidoka,
     git: "https://github.com/agentjido/jidoka.git",
     ref: "COMMIT_SHA"}
  ]
end
```

For local development against a checkout:

```elixir
def deps do
  [
    {:jidoka, path: "../jidoka"}
  ]
end
```

Then:

```bash
mix deps.get
```

### Configure a provider

The README examples use Anthropic through ReqLLM/Jido.AI:

```bash
export ANTHROPIC_API_KEY=sk-ant-...
```

In this repo, `.env` is also loaded automatically through `dotenvy`. Shell
environment variables win over `.env`.

### Model aliases

Jidoka owns a small alias layer under `config :jidoka, :model_aliases`. The
default `:fast` alias maps to `anthropic:claude-haiku-4-5`. You can also pass
direct model strings (`"anthropic:claude-haiku-4-5"`) or inline maps wherever
`model` is accepted.

### Alpha status

Jidoka is currently alpha. The beta surface (agents, tools, workflows,
imports, structured errors, and the Phoenix LiveView consumer) is being
stabilized. Pin a commit ref when consuming Jidoka from another app and expect
small breaking changes during the alpha-to-beta window. See
[ROADMAP.md](ROADMAP.md) for the current state.

## Try the demos and develop locally

### Built-in demo commands

```bash
mix jidoka chat --dry-run
mix jidoka imported --dry-run
mix jidoka workflow --dry-run
mix jidoka orchestrator --dry-run
```

Drop `--dry-run` to run a demo against a configured provider:

```bash
mix jidoka chat -- "Use one sentence to explain what Jidoka is."
```

The `examples/` directory contains focused, runnable demos for chat, structured
output, tools, workflows, orchestration, support, and more. Each canonical
example also supports `--verify` to exercise its tool and output contracts
without calling a provider:

```bash
mix jidoka lead_qualification --verify
```

### Local development

From this directory:

```bash
mix deps.get
mix compile
mix test
mix format
```

`mix quality` runs formatting, compiler warnings, Credo, Dialyzer, and
documentation coverage.

### Phoenix LiveView consumer app

`dev/jidoka_consumer/` is a Phoenix LiveView fixture that integrates a Jidoka
chat agent, an Ash-backed ticket resource, subagents, workflows, and handoffs.
Boot it on port 4002:

```bash
cd dev/jidoka_consumer
mix deps.get
PORT=4002 mix phx.server
```

See [Phoenix LiveView](guides/phoenix-liveview.md) for the integration walk-through.

## License

Apache-2.0. See [LICENSE](LICENSE).
