# Moto TODO

Curated feature roadmap for `Moto.Agent`, based on the framework research in
`../research/`.

The bias here is:

- match the current developer mental model for LLM agents
- keep the public DSL narrow
- integrate features one at a time
- avoid surfacing raw Jido/Jido.AI internals too early

## Next

- [x] `model`
  Add `model` to the `agent do ... end` DSL.
  Support:
  - alias atoms like `:fast`
  - direct model strings like `"anthropic:claude-haiku-4-5"`
  - inline ReqLLM/Jido.AI-compatible model maps
  - `%LLMDB.Model{}` structs

- [x] `tools`
  Add a small `tools do ... end` section for registering `Jido.Action` modules.
  Keep this very simple at first: no dynamic gating, no extra metadata beyond
  what the tool module already exposes.

- [x] `plugins`
  Add a small `plugins do ... end` section for registering `Moto.Plugin`
  modules.
  Keep this first pass narrow: plugins can contribute action-backed tools to
  the agent runtime without exposing broader plugin lifecycle/config hooks yet.

- [ ] `output`
  Add a first-class output concept.
  Start with:
  - `:text`
  - schema/module-backed structured output

- [ ] `context`
  Add explicit runtime-only context, separate from model-visible conversation
  history.
  This should become the Moto name for request-scoped runtime data.

## Soon After

- [ ] `memory`
  Start with conversation memory only.
  Keep long-term memory and retrieval for a later pass.

- [ ] `guardrails`
  Add input/output/tool guardrails by name instead of exposing policy internals.

- [ ] tool gating
  Allow tool availability to depend on runtime context.

## Later

- [ ] subagents / handoffs
  Treat these as second-layer features, not part of the beginner path.

- [ ] workflow
  Keep `workflow` separate from `agent`.

- [ ] resume / persistence
  Keep code-defined config separate from persisted run state.

- [ ] observability / inspection
  Add a clean way to inspect runs without turning the DSL into an ops surface.

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
