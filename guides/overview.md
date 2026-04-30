# Jidoka Guides

Jidoka is a small, opinionated harness over [Jido](https://github.com/agentjido/jido)
and [Jido.AI](https://github.com/agentjido/jido_ai). It gives you a single-agent
DSL, a runtime import path for JSON/YAML specs, and progressive opt-in for
tools, structured output, memory, workflows, subagents, and handoffs.

These guides are organized in tiers. Each guide focuses on one topic so you can
read only what your application needs.

Jidoka is beta software. The public surface is intentionally small: compiled
agents, imported agents, workflows, structured output, tracing, structured
runtime errors, and a few runtime facade functions. When a guide mentions Jido,
Jido.AI, Runic, or Jido Memory, treat those as implementation notes unless the
API is shown through the `Jidoka` namespace.

## Recommended Reading Path

For your first agent, read in this order:

1. [Getting Started](getting-started.html): build and run the smallest useful agent.
2. [Agents](agents.html): the 4-section DSL shape and compile-time validation.
3. one capability guide that matches your use case (start with [Tools](tools.html)).
4. [Structured Output](structured-output.html): typed JSON results with retries.
5. [Chat Turn](chat-turn.html): the turn lifecycle and public return shapes.

Everything else is opt-in.

## Guides Map

### Orientation

- [Overview](overview.html): this page.
- [Getting Started](getting-started.html): define, start, and chat with your first agent.

### Agent Fundamentals

- [Agents](agents.html): the 4-section DSL (`agent`, `defaults`, `capabilities`, `lifecycle`) and compile-time validation.
- [Models](models.html): aliases like `:fast`, direct provider strings, inline maps, and `%LLMDB.Model{}`.
- [Instructions](instructions.html): static strings, module resolvers, MFA, and dynamic per-turn instructions.
- [Context](context.html): request-scoped Zoi schemas, defaults, validation, per-turn merge, and forwarding.
- [Structured Output](structured-output.html): `output do schema retries on_validation_error`, `output: :raw`.
- [Chat Turn](chat-turn.html): the 7-step turn lifecycle and public return shapes.

### Capabilities

- [Tools](tools.html): `use Jidoka.Tool`, Zoi schemas, the `run/2` contract.
- [Ash Resources](ash-resources.html): `ash_resource` capability, AshJido action expansion, the `context.actor` requirement.
- [MCP Tools](mcp-tools.html): MCP endpoints, prefixes, app-config vs runtime registration.
- [Web Access](web-access.html): `web :search` / `:read_only`, the Brave key, `jido_browser`, SSRF posture.
- [Skills](skills.html): skill modules, `load_path`, and `allowed-tools` narrowing.
- [Plugins](plugins.html): `Jidoka.Plugin`, packaging reusable tools.

### Orchestration

- [Subagents](subagents.html): agent-as-tool delegation with `target`, `timeout`, `forward_context`.
- [Workflows](workflows.html): `use Jidoka.Workflow`, the steps DSL, refs (`input`/`from`/`context`/`value`), output, debug runs.
- [Handoffs](handoffs.html): the `handoff` capability, `conversation:`, owner registry, reset, vs subagent.

### Lifecycle Policy

- [Memory](memory.html): conversation memory, namespaces, capture, retrieve, inject.
- [Characters](characters.html): structured persona data and runtime override.
- [Hooks](hooks.html): `before_turn`, `after_turn`, `on_interrupt`.
- [Guardrails](guardrails.html): input, output, and tool guardrails.

### Imports

- [Imported Agents](imported-agents.html): the constrained JSON/YAML spec, `available_*` registries, `encode_agent/2`, and parity status.

### Operations And Observability

- [Errors](errors.html): error classes, `format_error/1`, `details.cause`.
- [Inspection](inspection.html): `inspect_agent/1`, `inspect_request/1`, `inspect_workflow/1`.
- [Tracing](tracing.html): `Jidoka.Trace`, run traces, Kino helpers.
- [Evals](evals.html): deterministic and live LLM evals.
- [Mix Tasks](mix-tasks.html): the `mix jidoka <name>` family with `--dry-run`, `--verify`, `--log-level`.
- [Livebooks](livebooks.html): the onboarding LiveBook series.
- [Phoenix LiveView](phoenix-liveview.html): `Jidoka.AgentView`, projection, runtime context boundary.
- [Examples](examples.html): example index by domain.
- [Production](production.html): release checklist and operational decisions.

## The Jidoka Mental Model

Jidoka is not a second runtime. It is an opinionated harness over Jido and
Jido.AI that narrows the public surface for common LLM-agent applications.

Use Jidoka when you want:

- a structured agent DSL with compile-time validation
- runtime context schemas that fail before a model call starts
- deterministic tools and workflows alongside chat agents
- low-risk public web search and read-only page access
- subagents for one-turn specialist delegation
- handoffs for conversation ownership transfer
- JSON/YAML imported agents with explicit allowlists
- structured runtime errors that can be formatted for users

Avoid starting with the most powerful feature. Start with a single agent and
add only the next capability the application actually needs.

## Core Concepts

An agent is a configurable chat runtime. It has stable identity, runtime
defaults, model-visible capabilities, and lifecycle policy.

A tool is deterministic application work exposed to a model as a callable
action. Jidoka tools are Zoi-first wrappers around Jido actions.

A subagent is an agent used as a tool. The parent remains in control of the
turn.

A workflow is a deterministic process owned by application code. It has
explicit input, ordered steps, dependencies, and output.

A handoff transfers future turns in a `conversation:` to another agent.

An imported agent is a constrained runtime representation of the same public
agent shape, loaded from JSON or YAML and resolved through explicit registries.

## Choosing An Orchestration Primitive

| Need | Use | Why |
| --- | --- | --- |
| Ask a specialist during one chat turn | `subagent` | Parent agent stays in control. |
| Run a known ordered process | `workflow` | Application owns the steps and dependencies. |
| Transfer future turns to another agent | `handoff` | Conversation ownership changes. |

See [Subagents](subagents.html), [Workflows](workflows.html), and
[Handoffs](handoffs.html) for the full picture.

## Beta Surface

The stable beta entrypoints are:

- `Jidoka.chat/3`
- `Jidoka.start_agent/2`
- `Jidoka.stop_agent/1`
- `Jidoka.whereis/2`
- `Jidoka.list_agents/1`
- `Jidoka.model/1`
- `Jidoka.format_error/1`
- `Jidoka.import_agent/2`
- `Jidoka.import_agent_file/2`
- `Jidoka.encode_agent/2`
- `Jidoka.inspect_agent/1`
- `Jidoka.inspect_request/1`
- `Jidoka.inspect_workflow/1`
- `Jidoka.handoff_owner/1`
- `Jidoka.reset_handoff/1`
- `Jidoka.Workflow.run/3`

Generated compiled agents also expose stable helpers such as `start_link/1`,
`chat/3`, `id/0`, `tools/0`, and capability name functions. Internal generated
modules and `__jidoka__/0` helpers are not the public authoring surface.

## Two Authoring Paths

Jidoka has two equal ways to describe the same conceptual agent.

The compiled DSL via `use Jidoka.Agent` is the recommended path for Elixir
developers. It gives you compile-time validation, formatter support, and
source-aware errors. See [Agents](agents.html).

The constrained runtime import path via `Jidoka.import_agent/2` lets teams
author agents in JSON or YAML, with executable pieces resolved through
explicit `available_*` registries. See [Imported Agents](imported-agents.html).
