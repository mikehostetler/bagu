# Moto TODO

Curated roadmap for `Moto.Agent`, based on the project review, current code,
and the framework research in `../research/`.

Current baseline:

- Commit: `4cc9c42 feat: define agent context with schema`
- Verification: `mix format && mix compile --warnings-as-errors && mix test`
- Test status: `158 tests, 0 failures`

The bias remains:

- keep the public DSL narrow
- keep Moto shaped around common LLM agent authoring
- hide raw Jido/Jido.AI runtime internals by default
- polish the current runtime before adding another orchestration layer

## Current Foundation

Moto now has a complete first-pass shape:

- [x] `model`
  Model aliases, direct model strings, inline maps, and `%LLMDB.Model{}` inputs
  resolve through Moto then Jido.AI.

- [x] `schema`
  Compiled agents now define runtime context with `schema Zoi.object(...)`
  inside `agent do`. Schema defaults become `Agent.context/0`, and per-turn
  `context:` is parsed through `Agent.context_schema/0`.

- [x] `tools`
  `Moto.Tool` is a Zoi-only wrapper over `Jido.Action`.

- [x] `skills`
  Jido.AI skill modules and runtime `SKILL.md` load paths are supported.

- [x] MCP tool sync
  Configured MCP endpoints can sync remote tools into Moto agents. Live
  filesystem MCP integration coverage exists.

- [x] `plugins`
  Moto plugins are first-class and can contribute action-backed tools.

- [x] dynamic `system_prompt`
  Static strings, module callbacks, and MFA callbacks are supported.

- [x] `hooks`
  DSL defaults and per-turn overrides support `before_turn`, `after_turn`, and
  `on_interrupt`.

- [x] `guardrails`
  Input, output, and tool guardrails exist with non-mutating validate, block, or
  interrupt semantics.

- [x] `context`
  Runtime `context:` is the public per-turn data plane. It is not automatically
  projected into model-visible prompts.

- [x] `memory`
  Conversation-first memory exists on top of `jido_memory`, with bounded
  retrieval and opt-in capture.

- [x] imported JSON/YAML agents
  Imported agents support the constrained runtime-safe feature subset with
  explicit registries for tools, skills, subagents, plugins, hooks, and
  guardrails. Imported agents still use plain default `context` maps.

- [x] `ash_resource` integration
  Ash resources can expand into generated `AshJido` action modules with
  context-based actor handling.

- [x] `subagents`
  Manager-pattern subagents are exposed as tool-like specialists. Runtime edges
  now include start-result normalization, peer timeout cancellation,
  context-forwarding policies, result modes, and request-scoped metadata.

- [x] observability / inspection
  `Moto.inspect_agent/1`, `Moto.inspect_request/1`, and `mix moto --log-level`
  provide a Moto-shaped debug story.

- [x] kitchen sink showcase
  `examples/kitchen_sink` and `mix moto kitchen_sink` provide a labeled
  all-features example for review and integration coverage. It is intentionally
  not the beginner path.

## Active Hardening Targets

These are implemented, but should keep getting sharper before Moto broadens.

### 1. Runtime Polish

- [ ] Raise coverage enforcement from the current spike baseline to the Jido
  package target of 90%.
  The quality tooling is wired, but the line coverage baseline is currently
  enforced at 70% until the package stabilizes.

- [ ] Make user-facing errors boring and actionable.
  Focus on context schema failures, missing MCP endpoint config, unavailable
  peer subagents, guardrail blocks, and failed tool sync.

- [ ] Keep CLI output simple.
  `mix moto chat`, `mix moto imported`, and `mix moto orchestrator` should stay
  REPL-first with one-shot prompt support and `--log-level info|debug|trace`.

- [ ] Keep inspection high-signal.
  Prefer curated Moto summaries over raw Jido signals, directives, or telemetry
  payloads.

### 2. Schema / Context DX

- [ ] Improve formatted schema validation errors returned from `Moto.chat/3`.
  The current tagged shape is correct, but it should be easier to read at the
  CLI and in examples.

- [ ] Add one example with a required context field.
  Show a clear failure when required runtime context is missing, then show the
  successful `context:` call.

- [ ] Decide whether imported specs should ever support schemas.
  Default answer for now: no arbitrary Zoi in JSON/YAML. Imported specs keep a
  plain `context` map unless Moto later defines a constrained portable schema
  format.

### 3. Subagents

- [ ] Keep hardening the manager pattern only.
  Do not add handoffs, workflows, peer mesh, or swarm behavior yet.

- [ ] Add one focused example for schema-aware context forwarding.
  Show parent context filtered by `forward_context`, then validated by the child
  agent schema.

- [ ] Continue tightening metadata and debug output.
  `inspect_request/1` and `--log-level debug|trace` should clearly show
  delegation name, target, child id, status, duration, context keys, and result
  preview.

- [ ] Keep failure surfaces normalized.
  Subagent tool failures should consistently return
  `{:error, {:subagent_failed, name, reason}}`.

### 4. MCP Client Support

- [ ] Harden configured MCP endpoint errors.
  Missing endpoint, failed server startup, bad command, and partial sync should
  fail clearly.

- [ ] Reduce Moto-owned MCP schema shims when possible.
  Moto currently handles real-world JSON Schema compatibility around synced MCP
  tools. Move proven cleanup upstream to `jido_mcp` when the shape is stable.

- [ ] Keep MCP scoped to client/tool sync.
  Do not implement "Moto as an MCP server" yet.

### 5. Memory

- [ ] Keep memory opt-in and conversation-first.
  Avoid exposing raw memory tools or broad retrieval configuration in v1.

- [ ] Harden namespace behavior.
  Recheck per-agent, shared, and context-derived namespace isolation.

- [ ] Improve failure handling.
  Memory read/write failures should not make normal chat behavior surprising.

## Dependency Baseline

- [x] `jido` uses Hex `~> 2.2` with override.
- [x] `jido_ai` uses Hex `~> 2.1` with override.
- [x] `ash_jido` points at GitHub `agentjido/ash_jido`.
- [x] `jido_mcp` points at GitHub `agentjido/jido_mcp`.
- [x] `jido_memory` points at GitHub `agentjido/jido_memory`.

Remaining dependency work:

- [ ] Remove direct `jido` / `jido_ai` overrides once git dependencies stop
  requiring older ranges.
- [ ] Prefer upstream fixes in `jido_mcp` and `jido_memory` over permanent Moto
  compatibility shims.

## Revisit Later

- [ ] delivery / artifact output
  Revisit when there is a concrete use case for images, PDFs, voice, or other
  artifacts. This likely belongs behind plugins or a dedicated delivery layer.

- [ ] tool exposure / gating
  Still too fuzzy for Moto. Guardrails validate tool calls; they should not
  become dynamic tool visibility until the mental model is obvious.

- [ ] handoffs
  Keep separate from current manager-pattern subagents.

- [ ] workflow
  Keep workflow separate from `agent`; do not fold graphs into `Moto.Agent`.

- [ ] resume / persistence
  Keep code-defined agent config separate from persisted run state.

## Intentionally Not Next

- [ ] Moto as an MCP server
- [ ] peer mesh / swarm coordination
- [ ] public reasoning strategy selection
- [ ] raw Jido signals / directives / state ops in the public DSL
- [ ] YAML-first authoring
- [ ] role / goal / backstory persona DSL

## Next Recommended Work

1. Polish schema/context DX.
   Make validation errors more readable and add one required-context example.

2. Add schema-aware subagent context forwarding coverage.
   This connects the new `schema` foundation directly to the manager-pattern
   subagent story.

3. Harden MCP endpoint failure behavior.
   Keep the scope to configured MCP clients syncing tools into Moto agents.

4. Keep observability focused.
   Improve `inspect_request/1` and CLI trace output where it helps users
   understand what Moto did without exposing low-level Jido machinery.
