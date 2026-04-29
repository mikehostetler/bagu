# Agents

A Jidoka agent is a compiled Elixir module that generates a Jido.AI runtime with
a smaller, validated authoring surface. This guide covers the four-section DSL
shape and the compile-time checks that keep agent modules consistent. For
runtime topics (instructions, models, the chat turn) see the linked guides
below.

## DSL Shape

The DSL has four top-level sections: `agent`, `defaults`, `capabilities`, and
`lifecycle`. Only `agent.id` and `defaults.instructions` are required.

```elixir
defmodule MyApp.SupportAgent do
  use Jidoka.Agent

  agent do
    id :support_agent
    description "Front-door customer support agent."

    schema Zoi.object(%{
      tenant: Zoi.string() |> Zoi.default("demo"),
      account_id: Zoi.string() |> Zoi.optional()
    })
  end

  defaults do
    model :fast
    instructions "You help customers with support questions."
  end

  capabilities do
    tool MyApp.Tools.LookupOrder
  end

  lifecycle do
    input_guardrail MyApp.Guardrails.SafePrompt
  end
end
```

### `agent do`

Stable identity and compile-time context schema:

- `id`: required, lower snake case atom.
- `description`: optional, free text.
- `schema`: optional compiled Zoi map/object schema for runtime context.
- `output do ... end`: optional structured output declaration.

### `defaults do`

Runtime defaults for every chat turn:

- `instructions`: required.
- `model`: optional, defaults to `:fast`.
- `character`: optional structured persona data.

### `capabilities do`

Model-visible or model-reachable features:

- `tool`
- `ash_resource`
- `mcp_tools`
- `web`
- `skill`
- `load_path`
- `plugin`
- `subagent`
- `workflow`
- `handoff`

### `lifecycle do`

Non-capability runtime policy:

- `memory`
- `before_turn`
- `after_turn`
- `on_interrupt`
- `input_guardrail`
- `output_guardrail`
- `tool_guardrail`

## Compile-Time Feedback

Jidoka rejects legacy or ambiguous placements at compile time so production
agents stay easy to inspect and import or export later. Examples:

- `agent.model` must move to `defaults.model`.
- `agent.system_prompt` must be renamed to `defaults.instructions`.
- top-level `tools`, `skills`, `plugins`, `subagents`, `hooks`, `guardrails`,
  and `memory` must move into `capabilities` or `lifecycle`.
- capability names must be unique across direct tools, Ash-generated tools, MCP
  tools, skill tools, plugin tools, web tools, subagents, workflows, and
  handoffs.

Treat these errors as structural feedback rather than friction. Verifiers cover
tools, Ash resources, skills, plugins, subagents, hooks, guardrails, memory,
and model resolution.

## Generated Functions

Each compiled agent module exposes a small set of stable helpers that mirror
the DSL. Use these for runtime introspection and for starting the agent:

```elixir
MyApp.SupportAgent.start_link(id: "support-1")
MyApp.SupportAgent.chat(pid, "Hello")

MyApp.SupportAgent.id()
MyApp.SupportAgent.name()
MyApp.SupportAgent.instructions()
MyApp.SupportAgent.configured_model()
MyApp.SupportAgent.model()
MyApp.SupportAgent.context_schema()
MyApp.SupportAgent.context()
MyApp.SupportAgent.tools()
MyApp.SupportAgent.tool_names()
MyApp.SupportAgent.subagents()
MyApp.SupportAgent.workflow_names()
MyApp.SupportAgent.handoff_names()
MyApp.SupportAgent.hooks()
MyApp.SupportAgent.guardrails()
```

Prefer these helpers and `Jidoka.inspect_agent/1` over reaching into private
internals. See [inspection.md](inspection.md) for richer surfaces and shared
helpers like `Jidoka.inspect_request/1`.

## See also

- [instructions.md](instructions.md): static, module, MFA, and dynamic prompts.
- [models.md](models.md): aliases, direct strings, inline maps, runtime resolution.
- [context.md](context.md): defining and parsing per-turn context.
- [chat-turn.md](chat-turn.md): the lifecycle of a single `Jidoka.chat/3` call.
- [overview.md](overview.md) and [tools.md](tools.md): the capability index and
  the most common capability.

## Imported agents

Imported JSON or YAML agents share the same four-section conceptual shape and
are loaded at runtime through `Jidoka.import_agent/2` and
`Jidoka.import_agent_file/2`. They expose the same return shapes through
`Jidoka.chat/3`. See [imported-agents.md](imported-agents.md) for the
constrained spec format and the small set of features that are compile-only.
