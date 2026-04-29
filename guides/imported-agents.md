# Imported Agents

Imported agents let applications load a constrained JSON/YAML representation of
the Jidoka agent shape at runtime.

They are not raw Elixir module loading. Every executable feature must resolve
through an explicit `available_*` registry supplied by the application.

This guide is the reference for the spec shape. For the conceptual behavior of
each capability, follow the cross-links into the dedicated guides.

## Spec Shape

Imported specs mirror the beta DSL sections (`agent`, `defaults`,
`capabilities`, `lifecycle`, plus an optional top-level `output`):

```json
{
  "agent": {
    "id": "sample_math_agent",
    "description": "Imported math assistant",
    "context": {"tenant": "demo", "channel": "json"}
  },
  "defaults": {
    "model": "fast",
    "instructions": "You are a concise assistant."
  },
  "capabilities": {
    "tools": ["add_numbers"],
    "skills": ["math-discipline"],
    "skill_paths": ["../skills"],
    "web": ["search"],
    "plugins": ["math_plugin"]
  },
  "lifecycle": {
    "hooks": {"before_turn": ["reply_with_final_answer"]},
    "guardrails": {"input": ["block_secret_prompt"]}
  }
}
```

Top-level flat specs are rejected. Keep the section layout.

## Parity Status

How the imported spec compares to the Elixir DSL, by capability:

| Capability        | Status      | Notes                                                |
| ----------------- | ----------- | ---------------------------------------------------- |
| Tools             | Full        | resolved via `available_tools`                       |
| MCP tools         | Full        | endpoint refs only, no raw modules                   |
| Skills            | Full        | refs plus `skill_paths`                              |
| Plugins           | Full        | resolved via `available_plugins`                     |
| Web access        | Full        | fixed Jidoka modes (`search`, `read_only`)           |
| Subagents         | Full        | resolved via `available_subagents`                   |
| Workflows         | Full        | resolved via `available_workflows`                   |
| Handoffs          | Full        | `auto` or `peer` targets                             |
| Memory            | Full        | constrained lifecycle memory subset                  |
| Hooks             | Full        | resolved via `available_hooks`                       |
| Guardrails        | Full        | resolved via `available_guardrails`                  |
| Characters        | Full        | string ref or inline map                             |
| Structured output | Full        | JSON Schema only (no portable Zoi)                   |
| Models            | Full        | alias string, provider string, or inline map         |
| Instructions      | Partial     | static string only (no module or MFA resolvers)      |
| Context           | Partial     | default map only (no portable Zoi schema)            |
| Ash resources     | Unsupported | use the Elixir DSL                                   |
| Raw browser tools | Unsupported | use the Elixir DSL with explicit modules             |
| `%LLMDB.Model{}`  | Unsupported | structs cannot serialize, use a string or inline map |

When a feature is `Partial` or `Unsupported`, prefer the compiled Elixir DSL
described in [agents.md](agents.md).

## Import From JSON Or YAML

```elixir
{:ok, agent} =
  Jidoka.import_agent(json,
    available_tools: [MyApp.Tools.AddNumbers],
    available_plugins: [MyApp.Plugins.Math],
    available_hooks: [MyApp.Hooks.ReplyWithFinalAnswer],
    available_guardrails: [MyApp.Guardrails.BlockSecretPrompt]
  )

{:ok, pid} = Jidoka.start_agent(agent, id: "json-agent")
{:ok, reply} = Jidoka.chat(pid, "Use add_numbers to add 2 and 3.")
```

Import from a file or encode back out:

```elixir
{:ok, agent} =
  Jidoka.import_agent_file("priv/agents/support_router.json",
    available_tools: [MyApp.Tools.LookupOrder]
  )

{:ok, json} = Jidoka.encode_agent(agent, format: :json)
{:ok, yaml} = Jidoka.encode_agent(agent, format: :yaml)
```

## Registries

Imported capabilities resolve by published names:

```elixir
Jidoka.import_agent(json,
  available_tools: [MyApp.Tools.AddNumbers],
  available_plugins: [MyApp.Plugins.Math],
  available_skills: [MyApp.Skills.MathDiscipline],
  available_subagents: [MyApp.ResearchAgent],
  available_workflows: [MyApp.Workflows.RefundReview],
  available_handoffs: [MyApp.BillingAgent],
  available_hooks: [MyApp.Hooks.ReplyWithFinalAnswer],
  available_guardrails: [MyApp.Guardrails.SafePrompt],
  available_characters: %{"support_advisor" => MyApp.Characters.SupportAdvisor}
)
```

Most registries accept either a list of modules or a map of published name to
module. Raw module strings in JSON/YAML are rejected because they bypass the
application allowlist. The `web` capability is the exception: it uses fixed
Jidoka modes and needs no registry.

## Instructions

`defaults.instructions` accepts a static string only. Module references and MFA
resolvers are not portable through import.

```json
{"defaults": {"instructions": "You are a concise assistant."}}
```

See [instructions.md](instructions.md) for the conceptual feature.

## Models

`defaults.model` accepts an alias string (`"fast"`, `"smart"`), a direct
provider string (`"openai:gpt-4o-mini"`), or an inline map. `%LLMDB.Model{}`
structs cannot be imported.

```json
{
  "defaults": {
    "model": {
      "provider": "openai",
      "id": "gpt-4o-mini",
      "base_url": "https://api.openai.com/v1"
    }
  }
}
```

See [models.md](models.md) for the conceptual feature.

## Context

`agent.context` accepts a default map. Per-turn `context:` still merges over
those defaults at chat time. Portable Zoi context schemas are not supported via
import.

```json
{
  "agent": {
    "id": "imported_support_agent",
    "context": {"tenant": "demo", "channel": "support"}
  }
}
```

See [context.md](context.md) for the conceptual feature.

## Structured Output

A top-level `output` block requests structured output via a JSON Schema map.
Only object-shaped JSON Schema is accepted (no portable Zoi).

```json
{
  "output": {
    "schema": {
      "type": "object",
      "properties": {
        "answer": {"type": "string"},
        "confidence": {"type": "number"}
      },
      "required": ["answer"]
    },
    "retries": 1,
    "on_validation_error": "repair"
  }
}
```

See [structured-output.md](structured-output.md) for the conceptual feature.

## Tools

`capabilities.tools` is a list of published tool names that resolve through
`available_tools`.

```json
{"capabilities": {"tools": ["add_numbers", "lookup_order"]}}
```

See [tools.md](tools.md) for the conceptual feature.

## MCP Tools

`capabilities.mcp_tools` references configured MCP endpoint names. An optional
`prefix` namespaces the imported tool names. Raw module references and inline
transport configs are not accepted.

```json
{
  "capabilities": {
    "mcp_tools": [{"endpoint": "billing_mcp", "prefix": "billing"}]
  }
}
```

See [mcp-tools.md](mcp-tools.md) for the conceptual feature.

## Skills

`capabilities.skills` lists skill refs (kebab-case) and `skill_paths` lists
directories to load skill packs from. Refs resolve through `available_skills`
when supplied.

```json
{
  "capabilities": {
    "skills": ["math-discipline", "billing-policies"],
    "skill_paths": ["../skills"]
  }
}
```

See [skills.md](skills.md) for the conceptual feature.

## Plugins

`capabilities.plugins` is a list of published plugin names that resolve through
`available_plugins`.

```json
{"capabilities": {"plugins": ["math_plugin", "telemetry_plugin"]}}
```

See [plugins.md](plugins.md) for the conceptual feature.

## Web Access

Imported specs opt into Jidoka's built-in low-risk web modes. Either a string
or an object form is accepted. `"search"` exposes `search_web`. `"read_only"`
exposes `search_web`, `read_page`, and `snapshot_url`. Raw browser action
configuration is not accepted.

```json
{"capabilities": {"web": [{"mode": "read_only"}]}}
```

See [web-access.md](web-access.md) for the conceptual feature.

## Subagents

`capabilities.subagents` references manager-side specialists by published id
that resolve through `available_subagents`. `target` accepts `"ephemeral"`
(default) or `"peer"` (with `peer_id` or `peer_id_context_key`).

```json
{
  "capabilities": {
    "subagents": [
      {
        "agent": "research_agent",
        "as": "research_agent",
        "description": "Ask the research specialist for concise notes",
        "target": "ephemeral",
        "timeout_ms": 30000,
        "forward_context": {"mode": "only", "keys": ["tenant", "session"]},
        "result": "structured"
      }
    ]
  }
}
```

See [subagents.md](subagents.md) for the conceptual feature.

## Workflows

`capabilities.workflows` references workflow ids that resolve through
`available_workflows`. `result` defaults to `"output"`. The spec references the
workflow's published id, not an Elixir module string.

```json
{
  "capabilities": {
    "workflows": [
      {
        "workflow": "refund_review",
        "as": "review_refund",
        "description": "Review refund eligibility.",
        "timeout": 30000,
        "forward_context": {"mode": "only", "keys": ["tenant", "session"]},
        "result": "structured"
      }
    ]
  }
}
```

See [workflows.md](workflows.md) for the conceptual feature.

## Handoffs

`capabilities.handoffs` references peer agent ids that resolve through
`available_handoffs`. `target` accepts `"auto"` (default: start or reuse a
deterministic target for the current conversation) or `"peer"` (with `peer_id`
or `peer_id_context_key`).

```json
{
  "capabilities": {
    "handoffs": [
      {
        "agent": "billing_specialist",
        "as": "transfer_billing_ownership",
        "description": "Transfer ongoing billing ownership.",
        "target": "auto",
        "forward_context": {"mode": "only", "keys": ["tenant", "account_id"]}
      }
    ]
  }
}
```

See [handoffs.md](handoffs.md) for the conceptual feature.

## Memory

`lifecycle.memory` uses the constrained memory shape. Strings select modes,
namespaces, capture targets, and inject targets.

```json
{
  "lifecycle": {
    "memory": {
      "mode": "conversation",
      "namespace": "context",
      "context_namespace_key": "session",
      "capture": "conversation",
      "retrieve": {"limit": 4},
      "inject": "instructions"
    }
  }
}
```

See [memory.md](memory.md) for the conceptual feature.

## Hooks

`lifecycle.hooks` lists hook names per stage that resolve through
`available_hooks`.

```json
{
  "lifecycle": {
    "hooks": {
      "before_turn": ["reply_with_final_answer"],
      "after_turn": ["log_turn_summary"],
      "on_interrupt": ["notify_supervisor"]
    }
  }
}
```

See [hooks.md](hooks.md) for the conceptual feature.

## Guardrails

`lifecycle.guardrails` lists guardrail names per stage that resolve through
`available_guardrails`.

```json
{
  "lifecycle": {
    "guardrails": {
      "input": ["block_secret_prompt"],
      "output": ["redact_pii"],
      "tool": ["require_authorized_caller"]
    }
  }
}
```

See [guardrails.md](guardrails.md) for the conceptual feature.

## Characters

`defaults.character` accepts a registered character name (resolved through
`available_characters`) or an inline character map.

```json
{"defaults": {"character": "support_advisor"}}
```

See [characters.md](characters.md) for the conceptual feature.

## Parity Rule

Imported agents are first-class Jidoka agents. When a Jidoka feature has a safe
portable representation, the imported format should support it. When a feature
cannot be represented safely, prefer an explicit registry or document the gap
in the Parity Status table above.

## See Also

- [agents.md](agents.md): the compiled Elixir DSL counterpart
- [mix-tasks.md](mix-tasks.md): tasks for inspecting and validating imported specs
- [errors.md](errors.md): how validation failures surface as `Jidoka.Error.ValidationError`
- [inspection.md](inspection.md): inspecting an agent before starting it
- [structured-output.md](structured-output.md): designing the JSON Schema you import
- [overview.md](overview.md): where imported agents fit in the Jidoka surface
