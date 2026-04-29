# Skills

Skills are prompt-level capability bundles built on Jido.AI skills. Use
them to ship reusable instructions, tool allowlists, and optional
action-backed tools as a single named unit. Skills are the right shape
when you want to compose an agent's behavior from versioned files on disk
rather than from raw strings in code.

## Minimal Example

```elixir
capabilities do
  skill "math-discipline"
  load_path "../skills"
end
```

`skill` registers a skill by name (or by Jido.AI skill module). `load_path`
points Jidoka at a directory or single `SKILL.md` file. At runtime, Jidoka
loads matching skills and merges them into the agent's effective
configuration.

## What A Skill Contributes

For each resolved skill, Jidoka:

- Renders the skill's prompt text into the agent's effective
  instructions, alongside `defaults.instructions`.
- Narrows the visible tool list when the skill declares
  `allowed-tools`. Only tools whose published names appear in that list
  remain visible to the model for the turn.
- Merges any action-backed tools the skill defines into the agent's tool
  registry, where they coexist with direct tools, plugins, Ash actions,
  MCP tools, and web tools.

## `skill` Vs `load_path`

- `skill "math-discipline"`: register a skill by published name. The skill
  must already be loadable (either compiled in or discovered through a
  `load_path` entry on the same agent).
- `skill MyApp.Skills.MathDiscipline`: register a Jido.AI skill module
  directly.
- `load_path "../skills"`: tell Jidoka to look in that directory for
  `SKILL.md` files at runtime. You can have multiple `load_path` entries.

You can declare any combination. Skill names must resolve to exactly one
loadable skill, and skill-provided tool names must not collide with other
capabilities.

## Worked Example

```elixir
defmodule MyApp.MathAgent do
  use Jidoka.Agent

  agent do
    id "math_agent"
  end

  defaults do
    instructions "You answer math questions."
  end

  capabilities do
    skill "math-discipline"
    load_path "priv/skills"
    tool MyApp.Tools.AddNumbers
  end
end
```

If `priv/skills/math-discipline/SKILL.md` declares `allowed-tools:
[add_numbers]`, the model only sees `add_numbers` for turns where the
skill applies, even though more tools may be attached at the agent level.

## See Also

- [tools.md](./tools.md)
- [plugins.md](./plugins.md)
- [instructions.md](./instructions.md)
- [agents.md](./agents.md)
- [characters.md](./characters.md)

## Imported Agents

Imported specs name skills and load paths as plain strings:

```json
{
  "capabilities": {
    "skills": ["math-discipline"],
    "skill_paths": ["../skills"]
  }
}
```

Skill modules are resolved by name through the application's available
skills, just like other capabilities. See
[imported-agents.md](./imported-agents.md).
