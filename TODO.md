# Moto TODO

Curated feature roadmap for `Moto.Agent`, based on the framework research in
`../research/`.

The bias here is:

- match the current developer mental model for LLM agents
- keep the public DSL narrow
- integrate features one at a time
- avoid surfacing raw Jido/Jido.AI internals too early

## Current Foundation

- [x] `model`
- [x] `tools`
- [x] `plugins`
- [x] `dynamic system_prompt`
- [x] `hooks`
- [x] `context`
- [x] `guardrails`
- [x] `memory`
- [x] `skills`
- [x] MCP tool sync
- [x] imported JSON/YAML agents
- [x] `ash_resource` integration
- [x] `subagents`
- [x] `observability / inspection`

The package now has a real first-pass shape:

- agent authoring with a small Spark DSL
- reusable tools, plugins, hooks, and guardrails
- runtime `context` as the public per-turn data plane
- conversation-first memory on top of `jido_memory`
- manager-pattern subagents as tool-like specialists
- public inspection for agent definitions and request summaries
- imported-agent parity for the main authoring features
- a shared runtime with `mix moto` demos and a local consumer app

## Next

- [ ] runtime polish
  Tighten the package around the current feature set before broadening it again.
  Specifically:
  - switch back from vendored `jido_ai` to an upstream release once the preflight callback patch lands
  - keep the boundaries sharp between plugins, hooks, and guardrails in docs and code
  - continue hardening subagent and memory edge cases as they show up

## Revisit Later

- [ ] `delivery` / artifact output
  Revisit this only when there is a concrete use case beyond chat.
  This is probably a better framing than generic “structured output”.
  Potential directions:
  - document / PDF generation
  - image generation
  - voice in / voice out
  - artifact-producing plugins

- [ ] typed `context`
  Runtime map-based context is the right starting point.
  Only add a typed/schema-backed context DSL if plain maps stop being sufficient.

- [ ] tool exposure / gating
  This still feels too fuzzy for Moto right now.
  Only revisit once there is a very clear user-facing mental model.

## Later

- [ ] handoffs
  Keep handoffs separate from the current manager-pattern subagent model.

- [ ] workflow
  Keep `workflow` separate from `agent`.

- [ ] resume / persistence
  Keep code-defined config separate from persisted run state.

## Intentionally Not Next

- [ ] role / goal / backstory personas
  Not a priority for the Moto surface.

- [ ] YAML-first configuration
  Keep authoring in Elixir code.

- [ ] public strategy selection
  Hide reasoning strategy details unless there is a strong DX reason to expose
  them later.

- [ ] raw signals / directives / state ops in the public DSL
  These should stay implementation details for as long as possible.
