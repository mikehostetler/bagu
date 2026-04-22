# Moto Usage Rules

Use these rules when generating Moto code or reviewing Moto examples.

## Agent DSL

- Define agents with `use Moto.Agent`.
- Put core configuration inside `agent do ... end`.
- Use `schema Zoi.object(...)` for runtime context validation.
- Prefer `context:` at runtime. Do not pass `tool_context:` to Moto public APIs.
- Keep prompts explicit. Moto does not automatically inject context into model
  prompts unless a system prompt, hook, tool, or memory configuration does so.

## Extensions

- Use `tools do` for explicit tool modules, Ash resources, and MCP tool sync.
- Use `plugins do` for Moto plugin modules.
- Use `hooks do` for turn-scoped transformations.
- Use `guardrails do` for validation-only input/output/tool checks.
- Use `subagents do` for manager-pattern delegation only. Do not model handoffs
  or workflow graphs as subagents.

## Imported Agents

- Use `Moto.import_agent/2` or `Moto.import_agent_file/2` for JSON/YAML specs.
- Resolve imported tools, hooks, guardrails, plugins, skills, and subagents
  through explicit `available_*` registries.
- Use `Moto.ImportedAgent.Subagent` when an Elixir manager agent delegates to a
  JSON/YAML-authored specialist.

## Examples

- Put runnable examples under `examples/`.
- Keep demo-only wiring out of `lib/`.
- Prefer simple examples first, then kitchen-sink coverage.
