# Bagu Usage Rules

Use these rules when generating Bagu code or reviewing Bagu examples.

## Agent DSL

- Define agents with `use Bagu.Agent`.
- Put core configuration inside `agent do ... end`.
- Use `schema Zoi.object(...)` for runtime context validation.
- Prefer `context:` at runtime. Do not pass `tool_context:` to Bagu public APIs.
- Keep prompts explicit. Bagu does not automatically inject context into model
  prompts unless a system prompt, hook, tool, or memory configuration does so.

## Extensions

- Use `capabilities do` for explicit tool modules, Ash resources, MCP tool
  sync, skills, plugins, subagents, and workflow capabilities.
- Use `lifecycle do` for memory, hooks, and guardrails.
- Use `subagent` for manager-pattern delegation inside an agent turn. Do not
  model handoffs or workflow graphs as subagents.
- Use `workflow` inside `capabilities do` when an agent should choose a known
  deterministic process as a tool-like capability.

## Workflow DSL

- Define deterministic workflows with `use Bagu.Workflow`.
- Put stable workflow identity and input schema inside `workflow do ... end`.
- Use `steps do` for `tool`, `function`, and `agent` steps.
- Use `output from(:step)` at module top level.
- Prefer explicit refs: `input(:key)`, `from(:step)`, `from(:step, :field)`,
  `context(:key)`, and `value(term)`.
- Use workflows when application code owns the sequence and data dependencies.
  Use agents for open-ended LLM turns and subagents for delegated capabilities
  inside one agent turn.
- Workflows may call agents as bounded steps, and agents may expose workflows
  as tool-like capabilities. Keep the boundary explicit: agents decide intent;
  workflows run fixed processes.
- Keep raw Runic concepts out of public Bagu code. Do not expose facts,
  directives, strategy state, or Runic nodes in user-authored workflows.

## Imported Agents

- Use `Bagu.import_agent/2` or `Bagu.import_agent_file/2` for JSON/YAML specs.
- Resolve imported tools, hooks, guardrails, plugins, skills, and subagents
  through explicit `available_*` registries.
- Use `Bagu.ImportedAgent.Subagent` when an Elixir manager agent delegates to a
  JSON/YAML-authored specialist.

## Examples

- Put runnable examples under `examples/`.
- Keep demo-only wiring out of `lib/`.
- Prefer simple examples first, then kitchen-sink coverage.

## Runtime Errors

- Public runtime APIs should return `{:ok, value}`, `{:interrupt, interrupt}`,
  or `{:error, %Bagu.Error.*{}}`.
- Do not expose raw internal error tuples from chat, workflow, subagent, MCP,
  memory, hook, or guardrail runtime boundaries.
- Use `Bagu.format_error/1` when printing errors in docs, demos, and CLIs.
- Preserve low-level causes in `error.details.cause`; do not require users to
  pattern-match on those causes.
