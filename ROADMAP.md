# Jidoka Roadmap

Updated: 2026-04-26

This is the single planning document for `jidoka`. It carries the current
assessment, tactical beta checklist, release gate, and post-beta direction.

## Current Status

Jidoka is an alpha, pre-beta package. It is not published to Hex yet.

The core design has been proven: Jidoka can be a narrow, developer-friendly
layer over Jido and Jido.AI without exposing raw signals, directives, state
operations, strategy internals, or request plumbing as the default authoring
surface.

The next phase is release discipline, not broadening. The highest-value work is
dependency posture, release packaging, docs, and runtime hardening around the
surface that already exists.

## Product Direction

Jidoka should grow through clear adjacent nouns, not by turning `Jidoka.Agent`
into a catch-all runtime.

- `agent` is the executable chat turn unit.
- `tool` is a model-callable deterministic capability.
- `model`, `instructions`, `context`, `memory`, `output`, and `middleware` style
  lifecycle concepts should remain familiar to developers coming from modern LLM
  agent frameworks.
- `workflow` coordinates explicit multi-step deterministic work.
- `character` shapes identity, voice, and prompt persona.
- `web` is constrained read-only public web access, not browser control.
- `handoff` transfers conversation/control ownership.
- `team` or `pod` is a future durable supervised group.

## Verified Baseline

Last verified: 2026-04-26.

Package checks:

- `mix deps.get`
- `mix compile`
- `mix test` (`276 tests, 0 failures`, `2 excluded` live LLM evals)
- `mix quality`

Example smoke checks:

- `mix jidoka chat --dry-run`
- `mix jidoka imported --dry-run`
- `mix jidoka workflow --dry-run`
- `mix jidoka workflow -- 7` (`%{value: 16}`)
- `mix jidoka orchestrator --dry-run`
- `mix jidoka kitchen_sink --log-level trace --dry-run`

Live provider checks with a configured Anthropic key:

- compiled chat demo returned `42` for the `add_numbers` prompt
- imported-agent demo returned `42` for the `add_numbers` prompt

Dev consumer app checks:

- `cd dev/jidoka_consumer && mix deps.get`
- `mix compile --warnings-as-errors`
- `mix test` (`16 tests, 0 failures`)
- `PORT=4002 mix phx.server`
- in-app browser load of `http://localhost:4002`

The dev site loaded successfully with the expected LiveView support console,
demo ticket queue, prompt buttons, runtime context, and no browser console
errors. The only browser warning was Tailwind's CDN warning, which is acceptable
for the local fixture but should not become the production asset story.

## Implemented Foundation

These are considered implemented for the beta candidate. They still need normal
hardening and documentation care, but they are no longer architectural unknowns.

- [x] Sectioned agent DSL: `agent`, `defaults`, `capabilities`, `lifecycle`
- [x] Required immutable `agent.id`
- [x] Required `defaults.instructions`
- [x] Model aliases and direct model resolution
- [x] Context schemas and default extraction
- [x] Direct tools with `use Jidoka.Tool`
- [x] Ash resource capability expansion
- [x] MCP tool sync
- [x] Constrained read-only web capabilities
- [x] Skills and runtime skill load paths
- [x] Plugins as deeper extension points
- [x] Hooks and guardrails
- [x] Conversation-first memory
- [x] Subagents as manager-controlled specialist tools
- [x] Explicit handoffs
- [x] Deterministic workflows via `Jidoka.Workflow`
- [x] Workflow capabilities exposed to agents as tools
- [x] JSON/YAML imported agents with explicit registries
- [x] Character/persona integration through `jido_character`
- [x] Jidoka/Splode runtime error normalization
- [x] Inspection helpers for agents, workflows, requests, and demos
- [x] CLI demo entrypoints under `mix jidoka`
- [x] Phoenix LiveView consumer spike under `dev/jidoka_consumer`

## Current Review

### Strong Signals

- The public mental model is clear: agents handle turns, workflows handle
  deterministic orchestration, handoffs transfer ownership, and the dev support
  app shows how the pieces fit at a Phoenix boundary.
- Imported agents are first-class constrained authoring surfaces, not a side
  path.
- Tool-like capabilities have useful breadth without losing shape: direct tools,
  Ash-generated actions, MCP-synced tools, skills, plugins, web tools,
  subagents, workflows, and handoffs all participate in duplicate-name checks.
- Error normalization is Jidoka-shaped and demos use `Jidoka.format_error/1`
  where user-facing output matters.
- The examples are layered correctly: chat and imported are simple, workflow is
  deterministic, orchestrator shows delegation, dev support shows app
  integration, and kitchen sink stays a showcase.

### Recent Findings

- Fixed: `dev/jidoka_consumer` dependency resolution now accounts for
  package-level `jido_browser` by using runtime `floki >= 0.38.0`.
- Fixed: planning docs are consolidated into this single roadmap.
- Fixed: root Jido ecosystem Git dependencies are pinned to explicit commit
  refs, and `dev/jidoka_consumer` no longer depends on sibling `jido` or
  `ash_jido` paths.
- Remaining: Tailwind CDN usage in the dev site is fine for a local fixture but
  should move to the normal Phoenix asset pipeline if the app becomes a public
  demo.
- Remaining: dependency posture still needs periodic review as upstream packages
  publish tags or Hex releases.
- Remaining: decide whether `Jidoka.Web` needs DNS-resolution checks to block
  public hostnames that resolve to private addresses before public beta.

## Active Beta Priorities

### 1. Dependency Posture

- [x] Pin root Jido ecosystem Git dependencies to explicit commit refs.
- [x] Move `jido_runic` from a sibling path dependency to a pinned Git ref.
- [x] Keep the dev consumer app using local `jidoka` while resolving sibling
  Jido ecosystem packages through Hex or pinned Git refs.
- [ ] Replace pinned Git refs with Hex releases or tags where practical.
- [ ] Decide whether `jido_runic`, `jido_memory`, `jido_mcp`,
  `jido_character`, and `ash_jido` need coordinated beta tags.
- [ ] Remove direct `override: true` entries once upstream dependency ranges
  align.
- [ ] Keep the dev consumer dependency graph resolving after package-level
  dependency changes.

### 2. Release Packaging

- [ ] Update `CHANGELOG.md` for the alpha-to-beta surface.
- [ ] Review `mix.exs` package metadata, docs groups, extras, and links.
- [ ] Decide whether `usage-rules.md` should be package-facing, org-facing, or
  both.
- [ ] Mark experimental modules and APIs clearly in docs.
- [ ] Decide whether the coverage gate should stay at 70% for alpha or move to
  80% for beta. Keep 90% as the v1 target.

### 3. Examples And Demos

- [ ] Keep focused examples first: chat, imported, workflow, orchestrator, dev
  support app.
- [ ] Keep `examples/kitchen_sink` positioned as a showcase, not the onboarding
  path.
- [ ] Run one real provider-backed compiled demo and one imported-agent demo
  before a beta tag.
- [ ] Keep live LLM evals excluded by default and documented with required env
  vars.
- [ ] Keep the smoke commands in this file current.

### 4. Dev Consumer Site

- [x] Ensure `dev/jidoka_consumer` resolves after `jido_browser` was added.
- [x] Compile the consumer app with warnings as errors.
- [x] Run the consumer test suite.
- [x] Boot the Phoenix endpoint on port `4002`.
- [x] Browser-check the root LiveView.
- [ ] Replace Tailwind CDN usage if the consumer app becomes more than a local
  dev fixture.
- [x] Keep `jidoka` as the only local path dependency in the dev app.

### 5. Runtime Hardening

- [ ] Decide whether `Jidoka.Web` needs DNS-resolution checks to block private
  targets reached through public hostnames before public beta.
- [ ] Add more formatted-error regression tests around nested subagent,
  workflow, MCP, memory, hook, and guardrail failures.
- [ ] Recheck memory namespace isolation for per-agent, shared, and
  context-derived namespaces.
- [ ] Improve `inspect_request/1` trace detail for delegation, memory, MCP
  sync, hooks, guardrails, workflows, and handoffs.
- [ ] Move proven MCP JSON Schema cleanup upstream to `jido_mcp` when stable.

## Pre-Beta Release Gate

Run from `jidoka/`:

```bash
mix deps.get
mix format --check-formatted
mix compile --warnings-as-errors
mix test
mix credo --min-priority higher
mix dialyzer
mix quality
```

Run example smoke checks:

```bash
mix jidoka chat --dry-run
mix jidoka imported --dry-run
mix jidoka workflow --dry-run
mix jidoka workflow -- 7
mix jidoka orchestrator --dry-run
mix jidoka kitchen_sink --log-level trace --dry-run
```

Run dev consumer checks:

```bash
cd dev/jidoka_consumer
mix deps.get
mix compile --warnings-as-errors
mix test
PORT=4002 mix phx.server
```

Then open `http://localhost:4002` and confirm the LiveView renders without
console errors.

## Milestone History

### Done For Beta Candidate

- Workflow spike with `jido_runic`
- Workflow MVP
- Runtime error normalization
- Public API stabilization
- Character integration
- Handoff MVP
- Constrained web capability
- Phoenix LiveView consumer spike

### Active

- Beta release prep
- Dependency posture for public beta and the `agentjido` org move
- Release notes and changelog
- Final example and dev-site smoke checks

## Post-Beta Direction

### Teams Or Pods

Use Jido Pods as the likely runtime substrate for durable supervised groups:
named nodes, dependencies, adoption, reconciliation, mutation, and supervision.
Prefer `team` publicly unless direct `pod` language proves clearer for
Elixir/Jido users.

### Crew-Style Recipes

Crew-style behavior should be built from Jidoka primitives:
`agent + workflow + character + handoff + team`. Do not copy YAML-first
authoring or role/goal/backstory as the core DSL.

Possible recipes:

- research-and-write team
- manager/reviewer/executor team
- planning workflow with specialist handoffs
- durable workspace team backed by Pods

## Intentionally Not Beta

- Jidoka as an MCP server
- Public raw Jido signals, directives, state ops, or strategy configuration
- Peer mesh or swarm coordination
- Durable workflow persistence
- Planner-generated workflows
- Broad direct Runic component authoring
- YAML-first authoring
- Artifact delivery for images, PDFs, voice, or files
- Dynamic tool exposure/gating beyond current guardrail validation
