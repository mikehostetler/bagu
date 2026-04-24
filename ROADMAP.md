# Bagu Roadmap

Updated: 2026-04-23

This roadmap is the high-level guide for moving Bagu toward beta and then into
the next orchestration layers. `TODO.md` remains the tactical checklist; this
file explains sequencing, scope, and boundaries.

## Product Direction

Bagu should stay a narrow, developer-friendly layer over Jido and Jido.AI. The
core design line is:

- `agent` is the executable unit.
- `workflow` coordinates explicit multi-step work.
- `character` shapes identity, voice, and prompt persona.
- `handoff` transfers conversation/control ownership.
- `team` or `pod` represents a durable supervised group.

Do not let `Bagu.Agent` absorb every concept. The package should grow by adding
clear adjacent nouns, not by turning the agent DSL into a catch-all runtime.

## Milestone Order

### 1. Workflow Spike With `jido_runic`

Goal: prove the workflow substrate before committing the public Bagu API.

Status: done.

Scope:

- Use the local `../jido_runic` checkout as a path dependency in a feature
  branch.
- Build the smallest Bagu-owned proof that can compile a workflow and run it.
- Decide whether Bagu should use direct `Runic.Workflow` execution,
  `Jido.Runic.Strategy`, or both.
- Decide how Bagu agent calls become workflow nodes.
- Identify any required upstream changes in `jido_runic`.

Exit criteria:

- One tiny local workflow runs end-to-end.
- We know the runtime path for the MVP.
- We have a short design note for the public `Bagu.Workflow` shape.

### 2. Workflow MVP

Goal: land the missing beta feature.

Status: done.

Scope:

- Add `Bagu.Workflow`.
- Support workflow id, description, input schema, steps, dependencies, output
  selection, and inspection.
- Support agent-backed steps and deterministic function/action steps.
- Compile Jido Action-backed steps through `Jido.Runic.ActionNode` where that is
  the right fit.
- Return Bagu/Splode errors.
- Add one focused example that is not the kitchen sink.
- Add docs explaining when to use an agent, subagent, or workflow.

Out of scope:

- Durable persistence.
- Planner-generated workflows.
- Crew/team abstraction.
- Public raw Runic graph authoring.

### 3. Runtime Error Normalization

Goal: make every important runtime failure readable and predictable before beta.

Status: done.

Scope:

- Normalize workflow errors into `Bagu.Error`.
- Normalize subagent failures.
- Normalize MCP endpoint startup, command, conflict, and partial-sync failures.
- Normalize memory read/write failures and define which failures are soft vs
  hard.
- Ensure CLI demos call `Bagu.format_error/1`.
- Add stable tests for multi-error formatting.

Ordering note:

Do this after the workflow MVP so workflow errors are included in the same error
taxonomy. Otherwise the error design will need to be reopened immediately.

Detailed plan:

1. Define the runtime error contract.
   - Keep public runtime calls returning `{:ok, value}` or
     `{:error, %Bagu.Error.*{}}`.
   - Treat raw strings, atoms, tuples, exits, and third-party exceptions as
     internal causes that must be wrapped before crossing a Bagu public
     boundary.
   - Preserve original reasons under `details.cause` or a narrower
     context-specific key so debugging does not lose information.
   - Standardize core metadata keys:
     `:operation`, `:agent_id`, `:workflow_id`, `:step`, `:target`, `:phase`,
     `:field`, `:value`, `:timeout`, `:request_id`, `:cause`.

2. Add a normalization module.
   - Introduce `Bagu.Error.Normalize` as the single place that turns known raw
     runtime reasons into `Bagu.Error.ValidationError`,
     `Bagu.Error.ConfigError`, or `Bagu.Error.ExecutionError`.
   - Keep the existing constructors in `Bagu.Error`, but route boundary code
     through named normalizers such as:
     `chat_error/2`, `workflow_error/2`, `subagent_error/2`,
     `mcp_error/2`, `memory_error/2`, `hook_error/2`, and
     `guardrail_error/2`.
   - Make unknown shapes deterministic by wrapping them as execution or
     internal errors with the inspected cause in details.

3. Improve formatting.
   - Expand `Bagu.Error.format/1` so it formats Splode classes, multi-errors,
     nested causes, workflow step failures, subagent failures, MCP endpoint
     failures, and memory failures.
   - Keep formatting stable and user-facing: one short headline plus sorted
     field bullets for validation details.
   - Ensure CLI demos and debug summaries never fall back to raw `inspect/1`
     for known Bagu errors.

4. Normalize workflow errors first.
   - Audit `Bagu.Workflow.Runtime` for raw reasons produced by input parsing,
     context refs, imported-agent refs, action execution, agent execution,
     timeouts, invalid step results, and output selection.
   - Ensure every `Bagu.Workflow.run/3` error has workflow id, step name when
     applicable, target, operation, and original cause.
   - Add formatting tests for invalid input, missing context refs, missing
     imported agents, step failure, timeout, and invalid output refs.

5. Normalize subagent errors.
   - Replace public `{:subagent_failed, name, reason}`,
     `{:child_error, reason}`, `{:peer_not_found, peer}`, timeout, invalid
     task, invalid child result, and peer mismatch shapes with
     `Bagu.Error.ExecutionError` or `Bagu.Error.ValidationError`.
   - Preserve child request metadata and peer target details in error metadata.
   - Update parent-agent tests so subagent failures are asserted as structured
     Bagu errors and formatted messages are stable.

6. Normalize MCP errors.
   - Wrap endpoint registration conflicts, startup failures, sync failures,
     command failures, tool limit failures, missing `jido_ai`, partial sync
     errors, and generated tool validation failures.
   - Distinguish hard failures from partial sync warnings. Hard failures should
     return `{:error, %Bagu.Error.*{}}`; partial sync should return successful
     sync metadata with structured warning entries.
   - Add tests for conflict, startup failure, partial sync, missing dependency,
     and endpoint command errors.

7. Normalize memory errors.
   - Define which memory failures are hard:
     invalid memory config, missing required context namespace keys, invalid
     namespace setup, and write failures when persistence was explicitly
     requested.
   - Define which memory failures are soft:
     optional retrieval misses, empty memory, and disabled/missing plugin cases
     that should not stop an agent turn.
   - Wrap `jido_memory` and Jido plugin errors with agent id, namespace,
     lifecycle phase, and original cause.
   - Add tests around retrieve/build/persist phases and kitchen sink memory
     behavior.

8. Normalize hooks and guardrails.
   - Wrap invalid request refs, invalid stages, hook callback failures,
     guardrail callback failures, guardrail tool errors, interrupts, and
     invalid callback return shapes.
   - Keep interrupt semantics explicit: interrupts should remain interrupt
     outcomes where expected, but invalid interrupt shapes should become
     validation errors.

9. Build an error matrix test suite.
   - Add table-driven tests that exercise each public runtime boundary:
     `Bagu.chat/3`, `Bagu.Agent.prepare_chat_opts/2`,
     `Bagu.Workflow.run/3`, subagent tools, MCP sync, and memory lifecycle.
   - Assert both struct class and formatted output.
   - Add regression tests proving unknown raw errors are wrapped rather than
     leaked.

10. Update docs and examples.
    - Document `Bagu.format_error/1` as the recommended display path.
    - Add a short README section showing validation, config, and execution
      errors.
    - Update usage rules to say public runtime APIs return Bagu/Splode errors
      and examples should not pattern-match on raw internal tuples.

Exit criteria:

- Public Bagu runtime APIs do not leak known raw string/atom/tuple reasons.
- `Bagu.format_error/1` produces stable messages for validation, config,
  execution, multi-error, workflow, subagent, MCP, memory, hook, and guardrail
  failures.
- Existing demos print formatted errors.
- The full release gate passes.

### 4. Public API Stabilization

Goal: freeze the beta public surface.

Status: done.

Scope:

- Review all public modules and function names.
- Decide top-level API boundaries, especially `Bagu.chat/3`,
  `Bagu.Workflow.run/3`, and whether a broader `Bagu.run/3` belongs in beta.
- Ensure docs use `instructions`, not `system_prompt`, except for internal Jido
  mapping notes.
- Ensure examples use the beta DSL shape and parenless style.
- Confirm imported JSON/YAML specs match the beta section layout.
- Update README, usage rules, changelog, docs groups, and package metadata.
- Run the full release gate and demo smoke checks.

Detailed plan:

1. Inventory the public surface.
   - List exported modules and functions from `lib/bagu`.
   - Separate intended beta API from implementation modules.
   - Mark internal modules with `@moduledoc false` where they should not be
     presented as public.
   - Confirm ExDoc grouping matches the intended public story.

2. Freeze top-level runtime APIs.
   - Confirm `Bagu.chat/3`, `Bagu.start_agent/2`, `Bagu.stop_agent/1`,
     `Bagu.format_error/1`, `Bagu.Workflow.run/3`, and
     `Bagu.inspect_workflow/1` are the intended beta entrypoints.
   - Decide whether `Bagu.run/3` belongs in beta or should be deferred.
   - Ensure successful return shapes and error return shapes are documented and
     tested at public boundaries.

3. Freeze the Agent DSL.
   - Confirm `agent`, `defaults`, `capabilities`, and `lifecycle` are the beta
     sections.
   - Confirm `instructions` is the only public prompt field.
   - Audit examples and imported specs for stale `system_prompt`, legacy flat
     placement, or old `Moto` naming.
   - Keep Jido-specific terms out of public docs unless they explain an internal
     adapter boundary.

4. Freeze the Workflow DSL.
   - Confirm workflow `id`, `description`, `input`, `steps`, and `output` are
     the beta contract.
   - Confirm `tool`, `function`, and `agent` are the only beta step kinds.
   - Confirm direct `Runic` concepts stay internal.
   - Decide whether workflow inspection output is stable enough for beta or
     should be marked experimental.

5. Decide the agent/workflow integration boundary.
   - Evaluate whether beta needs an agent capability adapter for workflows, for
     example `workflow MyWorkflow, as: :review_refund`.
   - If included, keep it narrow: expose workflows to agents as tool-like
     capabilities, but continue running them through `Bagu.Workflow`.
   - If deferred, document the current rule clearly: workflows may call agents,
     but agents do not yet call workflows directly.
   - Use the support example as the decision fixture because it already exposes
     both directions.

6. Stabilize errors and diagnostics.
   - Confirm runtime errors are always Bagu/Splode errors at public boundaries.
   - Confirm `Bagu.format_error/1` is the only recommended display path.
   - Audit demo CLIs, evals, and debug output for raw `inspect(reason)` usage on
     known Bagu errors.

7. Stabilize examples and eval posture.
   - Keep kitchen sink broad, but make focused examples the primary docs path.
   - Ensure support, workflow, imported, orchestrator, and chat demos all use
     the renamed `mix bagu` commands.
   - Keep live LLM evals excluded by default and document required environment
     variables.

8. Stabilize dependency posture.
   - Decide which local path dependencies are acceptable for beta.
   - For public Hex beta, replace local paths with Hex releases, Git refs, or
     pinned tags.
   - Document any dependency that remains intentionally experimental.

9. Run the beta release gate.
   - `mix format --check-formatted`
   - `mix compile --warnings-as-errors`
   - `mix test`
   - `mix credo --min-priority higher`
   - `mix dialyzer`
   - `mix quality`
   - Smoke all `mix bagu ... --dry-run` demos.

Exit criteria:

- The beta API is documented and intentionally named.
- Tactical TODO items blocking beta are either done or explicitly deferred.

### 5. Beta Release

Goal: publish or tag a coherent beta that users can evaluate.

Scope:

- Final release gate.
- Changelog and migration note for the beta DSL.
- Dependency posture decision:
  - internal beta can tolerate path/GitHub dependencies;
  - public Hex beta should prefer Hex releases or pinned tags.
- Release notes that clearly state what is stable, experimental, and deferred.

## Post-Beta Milestones

### 6. Characters Via `jido_character`

Goal: add persona/voice composition without bloating `Bagu.Agent`.

Status: basic Bagu integration done; Bagu now has a direct Git dependency on
`jido_character`. Public Hex beta still needs a dependency posture decision:
Hex release, pinned tag, or another stable source.

Candidate package:

- `jido_character` exists at `https://github.com/agentjido/jido_character`.
- It is not currently available through `mix hex.info jido_character`.
- It provides Zoi-validated character maps, `use Jido.Character`, identity,
  personality, voice, knowledge, memory, instructions, renderers, and ReqLLM
  context rendering.

Likely Bagu scope:

- Add `defaults.character MyApp.Characters.SupportAdvisor` or similar. Done.
- Compose rendered character output with `defaults.instructions`. Done.
- Support per-call `character:` overrides. Done.
- Support imported `defaults.character` inline maps and `available_characters`
  refs. Done.
- Define precedence between static instructions, dynamic instructions, and
  character-rendered prompt sections. Done: character first, instructions
  second, skills and memory afterward.
- Keep character memory distinct from `jido_memory` until the model is clear.

Risk:

- Character rendering touches prompt composition, which is public and easy to
  overfit. Continue refining through examples before expanding the DSL.

### 7. Handoffs

Goal: support explicit control transfer between agents.

Distinction:

- Subagents are "agent as tool": the parent agent remains in control.
- Handoffs transfer ownership of the next turn or phase to another agent.

Scope questions:

- Who owns the thread after handoff?
- How is memory namespace selected?
- Which context keys are forwarded?
- Which guardrails and hooks apply after transfer?
- Does control ever return automatically?
- How is the final response surfaced?

Dependency:

- Workflows should land first so multi-step orchestration is not confused with
  conversation ownership transfer.
- Characters should land first or in parallel if handoff examples depend on
  strong specialist identity.

### 8. Pods And Durable Teams

Goal: expose durable supervised agent groups when users need long-lived teams or
workspace-level topology.

Underlying runtime:

- Jido Pods model canonical topology, eager/lazy node reconciliation, adoption,
  nested pods, partitioning, and runtime mutation.

Likely Bagu noun:

- Prefer `team` publicly unless direct `pod` language proves clearer for
  Elixir/Jido users.

Scope:

- Define named team members.
- Start or lookup durable teams by id.
- Inspect member status.
- Ensure lazy members.
- Decide how teams interact with workflows and handoffs.

Out of scope for first pass:

- Full topology mutation DSL.
- Complex nested teams.
- Swarm-like peer mesh behavior.

### 9. Crew-Style Recipes

Goal: provide higher-level coordination patterns after the underlying pieces are
stable.

Positioning:

- CrewAI is useful as product vocabulary: agents, tasks, crews, flows, manager
  process, planning, memory, and callbacks.
- Bagu should not copy YAML-first authoring or role/goal/backstory as the core
  DSL.
- Crew-style behavior should be built from Bagu primitives:
  `agent + workflow + character + handoff + team`.

Possible recipes:

- Research-and-write team.
- Manager/reviewer/executor team.
- Planning workflow with specialist handoffs.
- Durable workspace team backed by Pods.

## Current Priority

The next work should follow this order:

1. Beta release prep.
2. Dependency posture for a public beta.
3. Handoff design and implementation.
4. Pods/team-level coordination planning.
5. Crew-style recipe examples after the lower-level primitives are stable.

Characters are integrated for the beta candidate. Handoffs, Pods, and
Crew-style coordination remain important, but they should not block the first
beta unless the beta positioning explicitly requires them.
