# Moto Beta TODO

Updated: 2026-04-22

This file is the working beta-release roadmap for `moto`. It intentionally
separates the current agent foundation from the next orchestration layer so we
can ship a coherent beta instead of continuously expanding `Moto.Agent`.

## Current Baseline

- Branch: `main`
- Current head reviewed: `49764d6 feat: improve schema context error dx`
- Last known full verification: `mix quality` and `mix test`
- Last known test status: `169 tests, 0 failures`
- Package status: experimental, pre-beta, not Hex-published

The beta bias:

- keep Moto narrow, developer-friendly, and strongly validated at compile time
- keep Jido and Jido.AI as the runtime foundation
- hide raw Jido signals, directives, state ops, and strategy internals by
  default
- prefer polished agent, context, memory, tool, and workflow paths over broad
  runtime exposure

## Locked Foundation

These pieces are now considered the working beta foundation. They can be
hardened, but the high-level direction should not churn without a concrete
release reason.

- [x] Beta agent DSL shape
  `agent`, `defaults`, `capabilities`, and `lifecycle` are the public sections.
  Legacy flat declarations now fail at compile time.

- [x] Core immutable agent definition
  `agent.id` is required and immutable. `agent.description` and the compiled
  context `schema` live with the identity definition.

- [x] Runtime defaults
  `defaults.instructions` is required. `defaults.model` is optional. Both stay
  out of the immutable agent identity.

- [x] Public `instructions` language
  Moto exposes `instructions`; internally it still maps to Jido's
  `system_prompt` APIs where required.

- [x] Context schema and defaults
  Compiled Zoi schemas live in `agent.schema`. `Moto.Context.defaults/1`
  preserves defaulted fields even when other fields are required.

- [x] Splode-backed error DX
  Moto now has `Moto.Error`, `Moto.format_error/1`, validation errors, config
  errors, runtime errors, and user-facing context/schema formatting.

- [x] Capabilities
  Direct tools, Ash-generated tools, MCP tools, skills, load paths, plugins,
  and manager-pattern subagents all live under `capabilities`.

- [x] Lifecycle
  Memory, hooks, and guardrails live under `lifecycle`.

- [x] Memory integration
  Moto uses `jido_memory` through the normal Jido plugin path. Memory remains
  opt-in and conversation-first.

- [x] Imported specs
  JSON/YAML specs mirror the beta DSL section layout. Imported agents stay
  context-default-only for beta; they do not support portable schemas yet.

- [x] Demos and smoke paths
  `mix moto chat`, `mix moto imported`, `mix moto orchestrator`, and
  `mix moto kitchen_sink` exercise the primary examples.

## Beta Release Blockers

### 1. Workflow Design And MVP

Workflows are the outstanding missing product feature for beta. They should be
a separate top-level concept, not an expansion of `Moto.Agent`.

Research baseline:

- `jido_runic` is the candidate workflow integration layer, not Reactor.
- A local clone now exists at `../jido_runic`; use it for workflow planning and
  the first local path dependency iteration.
- `jido_runic` currently lives at `agentjido/jido_runic`, is clean on
  `main...origin/main`, and is not published on Hex yet. Reviewed head:
  `98e6add ci: finish shared workflow rollout to v3`.
- `jido_runic` depends on `runic`, a DAG workflow graph/runtime package. The
  local `jido_runic` mix currently asks for `runic ~> 0.1.0-alpha.4`; Hex has
  newer `runic` alphas available.
- The useful integration points are `Jido.Runic.ActionNode`,
  `Jido.Runic.Strategy`, `Jido.Runic.SignalFact`,
  `Jido.Runic.Directive.ExecuteRunnable`, `Jido.Runic.RunnableExecution`, and
  `Jido.Runic.Introspection`.
- `jido_runic` already has examples for research pipelines, branching,
  delegated child-agent execution, and step-mode debugging.
- Sources reviewed:
  `../jido_runic/AGENTS.md`,
  `../jido_runic/README.md`,
  `../jido_runic/mix.exs`,
  `../jido_runic/lib`,
  `../jido_runic/examples`,
  `../jido_runic/test`,
  `https://github.com/agentjido/jido_runic`,
  `https://github.com/zblanco/runic`,
  `https://hex.pm/packages/runic`, and
  `https://jido.run/ecosystem/jido_lib`.

Required decisions:

- [ ] Decide the workflow backend.
  Default answer: build on `jido_runic` and Runic. The remaining work is to
  decide whether Moto compiles directly to `Runic.Workflow` structs, wraps
  `Jido.Runic.Strategy`, or supports both a direct one-shot runner and a
  strategy-driven AgentServer path.

- [ ] Decide how Jido Pods fit.
  Jido Pods manage long-lived agent topology: named nodes, dependencies,
  adoption, reconciliation, mutation, and supervision. That is valuable for
  future runtime topology, but it is not obviously the beta workflow execution
  model because it does not primarily model step input/output dataflow.

- [ ] Define the beta `Moto.Workflow` scope.
  The first version should cover deterministic app-owned orchestration around
  agents and functions. It should not become handoffs, peer mesh, autonomous
  swarms, or public Jido runtime strategy selection.

- [ ] Decide how much Runic language Moto should expose.
  Runic has facts, runnables, match/execute nodes, graph components, scheduler
  policies, run context, and external scheduler hooks. Moto should expose a
  smaller agent-workflow vocabulary and keep raw Runic concepts behind
  inspection/debug APIs unless users explicitly opt into interop.

Recommended MVP:

- [ ] `use Moto.Workflow`
- [ ] `workflow do id :lower_snake_case; description "..."; input Zoi.object(...) end`
- [ ] agent steps that call existing `Moto.Agent` or `Moto.ImportedAgent`
- [ ] function/tool steps for deterministic Elixir work between agent calls
- [ ] Jido Action-backed steps compiled to `Jido.Runic.ActionNode`
- [ ] explicit data wiring from workflow input, prior step result, static value,
  and workflow context
- [ ] sequential and DAG dependencies compiled into `Runic.Workflow.add/3`
- [ ] bounded parallel execution through Runic scheduling where dependencies
  allow it
- [ ] output selection from a named step or collected map
- [ ] `Moto.Workflow.run/3` returning Moto/Splode errors
- [ ] `Moto.inspect_workflow/1` backed by `Jido.Runic.Introspection`
- [ ] one CLI/demo workflow that is not the kitchen sink
- [ ] one step-mode or debug-mode path that proves we can inspect workflow
  progress without exposing low-level Jido machinery

Defer unless the backend makes them cheap and obvious:

- [ ] durable persistence
- [ ] external approvals
- [ ] long-running suspend/resume across VM restarts
- [ ] dynamic graph mutation
- [ ] planner-generated workflows
- [ ] swarm/peer coordination
- [ ] broad direct Runic component authoring from the Moto DSL

Validation requirements:

- [ ] require workflow id and validate lower snake case
- [ ] reject duplicate step names
- [ ] reject missing step references
- [ ] reject cyclic dependencies
- [ ] validate agent step modules implement the Moto agent surface
- [ ] validate input/context mappings against declared schemas where possible
- [ ] validate output references exist
- [ ] format workflow compile errors with the same section path, module, source
  location, invalid value, and fix-hint style used by `Moto.Agent`

Open design questions:

- [ ] Should workflow input schema use `input Zoi.object(...)` or mirror agents
  with `schema Zoi.object(...)`?
- [ ] Should agent steps accept only `prompt`/`context`, or should they expose a
  richer request object?
- [ ] Should workflow context be a separate data plane from workflow input, or
  should `input` be the only public per-run data plane?
- [ ] Should memory use the workflow run id, the agent id, or explicit
  conversation ids for multi-step agent calls?
- [ ] Should Moto represent agent calls as Jido Actions first, or should
  `jido_runic` grow a first-class Moto/Jido.AI agent node?
- [ ] Should Moto use `Jido.Runic.Strategy` for all workflow execution, or only
  for supervised/long-running workflows?
- [ ] How should Runic scheduler policies map to Moto concepts like timeout,
  retry, backoff, fallback, and failure mode?
- [ ] Should workflow step mode become part of the public beta API or remain a
  demo/debug feature?

### 2. Workflow Documentation And Examples

- [ ] Add a short workflow guide to `README.md`.
- [ ] Add `usage-rules.md` guidance for agents vs workflows.
- [ ] Add one focused `examples/workflow` demo.
- [ ] Add a `mix moto workflow` smoke command only if it stays simple.
- [ ] Add a workflow inspection/debug example.
- [ ] Make clear that subagents and workflows solve different problems:
  subagents are capabilities inside an agent turn; workflows are app-owned
  orchestration across steps.

### 3. Public API Stabilization

- [ ] Review all public modules for beta naming consistency.
- [ ] Ensure docs use `instructions`, not `system_prompt`, except when
  explaining the Jido mapping internally.
- [ ] Ensure examples use the parenless DSL style.
- [ ] Ensure all user-facing errors go through `Moto.format_error/1` in demos.
- [ ] Confirm imported JSON/YAML examples match the beta section layout.
- [ ] Decide whether `Moto.chat/3` remains the only top-level agent call or
  whether `Moto.run/3` is needed for workflows.

### 4. Runtime Error Normalization

Splode is now the canonical Moto error path. The remaining hardening work is to
make every important runtime edge readable without breaking the narrow public
surface.

- [ ] Normalize subagent tool failures into Moto/Splode runtime errors while
  preserving useful child-agent context.
- [ ] Normalize MCP endpoint startup, command, conflict, and partial-sync
  failures.
- [ ] Normalize memory read/write failures and decide which ones should be
  soft-fail vs hard-fail.
- [ ] Ensure guardrail block/interrupt formatting is readable in CLI output.
- [ ] Add stable tests for formatted multi-error output.

### 5. Release Readiness

- [ ] Raise or explicitly accept the coverage gate for beta.
  Current threshold is 70%. Recommended beta target is at least 80%, with 90%
  as the v1 target.

- [ ] Decide dependency publishing posture.
  Current Moto depends on GitHub branches for `jido_ai`, `jido_memory`,
  `jido_mcp`, and `ash_jido`. That may be acceptable for an internal beta, but
  a public Hex beta should prefer Hex releases or pinned tags.

- [ ] Add `jido_runic` as a direct dependency when workflow work starts.
  Start with `{:jido_runic, path: "../jido_runic"}` so Moto and Jido.Runic can
  iterate together in the monofolder. Before public beta, decide between a
  pinned GitHub dependency and landing a `jido_runic` Hex beta first. Do not
  rely on transitive `runic` availability for a public `Moto.Workflow` API.

- [ ] Remove direct overrides once upstream dependency ranges align.
  `jido` and `jido_ai` overrides are useful during ecosystem iteration, but
  should not be invisible release assumptions.

- [ ] Run the full release gate:
  `mix format --check-formatted`, `mix compile --warnings-as-errors`,
  `mix test`, `mix credo --min-priority higher`, `mix dialyzer`,
  and `mix quality`.

- [ ] Run demo smoke tests:
  `mix moto chat`, `mix moto imported`, `mix moto orchestrator`,
  and `mix moto kitchen_sink`.

- [ ] Review package metadata and docs groups before Hex publishing.

- [ ] Add or update `CHANGELOG.md` with the beta DSL break.

- [ ] Tag the beta API surface in docs so experimental internals are not
  accidentally treated as stable.

## Near-Term PR Plan

1. Workflow design spike
   Use the local `../jido_runic` checkout to inspect Jido.Runic, Runic, and
   Jido Pod APIs in detail, write the backend decision down, and commit to the
   beta workflow scope. Reactor is not the candidate unless `jido_runic` fails
   a concrete requirement.

2. Workflow DSL skeleton
   Add `Moto.Workflow` with Spark sections, entities, info helpers, compile-time
   validation, and inspection without a large runtime surface.

3. Workflow runtime MVP
   Add `Moto.Workflow.run/3`, agent-step execution, function/tool steps,
   input/context parsing, output selection, and Moto/Splode errors.

4. Workflow examples and docs
   Add the workflow guide, focused example, tests, and optional mix task smoke
   path.

5. Runtime hardening pass
   Normalize subagent, MCP, memory, and guardrail error formatting. Keep this
   separate from workflow implementation so failures are easier to review.

6. Beta release prep
   Update package docs, changelog, coverage threshold, and final smoke checklist.

## Hardening Backlog

These are important, but they should not distract from the workflow beta blocker
unless they fall out naturally while working on the release gate.

- [ ] Add schema-aware subagent context-forwarding docs and focused tests.
- [ ] Improve `inspect_request/1` trace detail for delegation, memory, MCP sync,
  hooks, and guardrails.
- [ ] Recheck memory namespace isolation for per-agent, shared, and
  context-derived namespaces.
- [ ] Move proven MCP JSON Schema cleanup upstream to `jido_mcp` when stable.
- [ ] Decide whether imported specs should ever support a constrained portable
  schema format.
- [ ] Add a migration note from legacy flat DSL declarations to the beta DSL.

## Intentionally Not Beta

- [ ] Moto as an MCP server
- [ ] public raw Jido signals, directives, state ops, or strategy configuration
- [ ] handoff DSL
- [ ] peer mesh or swarm coordination
- [ ] YAML-first authoring
- [ ] role/goal/backstory persona DSL
- [ ] artifact delivery for images, PDFs, voice, or files
- [ ] dynamic tool exposure/gating beyond current guardrail validation
- [ ] durable workflow persistence unless the selected backend makes a minimal
  version obvious

## Review Notes

- `Moto.Agent` is now in a good beta shape. The next architectural risk is
  overloading it with workflow concerns.
- `jido_runic` is the workflow candidate because it bridges Runic DAGs with
  Jido Actions, Signals, Strategy execution, directives, child delegation, and
  introspection.
- Reactor is no longer the planned workflow substrate for Moto.
- Jido Pod looks more like future supervised runtime topology than the first
  workflow execution model.
- Memory should remain an agent lifecycle feature first. Workflows should pass
  explicit context/conversation identifiers into agent steps rather than owning
  memory directly in the first beta.
- Subagents should remain a manager-agent capability. Workflows should be the
  recommended tool when the user wants explicit multi-step orchestration.
