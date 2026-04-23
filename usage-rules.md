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

- Use `capabilities do` for explicit tool modules, Ash resources, MCP tool
  sync, skills, plugins, and subagents.
- Use `lifecycle do` for memory, hooks, and guardrails.
- Use `subagent` for manager-pattern delegation inside an agent turn. Do not
  model handoffs or workflow graphs as subagents.

## Workflow DSL

- Define deterministic workflows with `use Moto.Workflow`.
- Put stable workflow identity and input schema inside `workflow do ... end`.
- Use `steps do` for `tool`, `function`, and `agent` steps.
- Use `output from(:step)` at module top level.
- Prefer explicit refs: `input(:key)`, `from(:step)`, `from(:step, :field)`,
  `context(:key)`, and `value(term)`.
- Use workflows when application code owns the sequence and data dependencies.
  Use agents for open-ended LLM turns and subagents for delegated capabilities
  inside one agent turn.
- Keep raw Runic concepts out of public Moto code. Do not expose facts,
  directives, strategy state, or Runic nodes in user-authored workflows.

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
