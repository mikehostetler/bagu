# Livebooks

The Jidoka Livebook series is a runnable onboarding path that mirrors the
written guides. Each notebook teaches one capability through a small, complete
example you can run in a fresh Livebook session, without a local checkout of
the repo. If the guides explain a feature, a notebook exercises it.

The series lives under the
[`livebook/`](https://github.com/agentjido/jidoka/tree/main/livebook)
directory in the repo and is numbered `01` through `21`. Notebook numbers are
roughly chronological by feature addition, not strict guide tier order: see the
index below for the mapping.

## Setup

Prerequisites:

- Livebook: install from [livebook.dev](https://livebook.dev) (`>= 0.19`).
- Provider key: most chat cells expect a Livebook secret named
  `ANTHROPIC_API_KEY`. Cells that need a secret fall back to a friendly
  missing-secret message instead of crashing.
- No local checkout required. Each notebook installs Jidoka from GitHub, usually
  at a pinned commit `ref`.

Every notebook starts with the same shape: a `Mix.install/2` cell that loads
`:jidoka` from GitHub and `:kino`, followed by a
`Jidoka.Kino.setup()` cell. After that, agent definition and chat cells use
the public facade (`Jidoka.chat/3`, `Jidoka.format_error/1`, and friends).

Provider-backed cells should run after the deterministic inspection and direct
tool/workflow cells, so a notebook stays useful even when no key is configured.
See [`getting-started.md`](getting-started.md) for the same flow outside
Livebook.

## Notebook index

| Notebook | Topic | Guide |
| --- | --- | --- |
| `01_hello_agent.livemd` | Minimal agent, inspection, first chat | [`agents.md`](agents.md), [`getting-started.md`](getting-started.md) |
| `02_tools_and_context.livemd` | Deterministic tools and runtime context | [`tools.md`](tools.md), [`context.md`](context.md) |
| `03_workflows_and_imports.livemd` | Workflow execution and JSON imports | [`workflows.md`](workflows.md), [`imported-agents.md`](imported-agents.md) |
| `04_errors_inspection_debugging.livemd` | Structured errors, inspection, traces | [`errors.md`](errors.md), [`inspection.md`](inspection.md), [`tracing.md`](tracing.md) |
| `05_hooks_and_guardrails.livemd` | Before/after hooks and input guardrails | [`hooks.md`](hooks.md), [`guardrails.md`](guardrails.md) |
| `06_memory.livemd` | Conversation memory capture and injection | [`memory.md`](memory.md) |
| `07_characters_and_instructions.livemd` | Characters and per-turn overrides | [`characters.md`](characters.md), [`instructions.md`](instructions.md) |
| `08_subagents.livemd` | Manager-controlled specialist agents | [`subagents.md`](subagents.md) |
| `09_handoffs.livemd` | Conversation ownership transfer | [`handoffs.md`](handoffs.md) |
| `10_skills_and_load_paths.livemd` | Module skills and `SKILL.md` load paths | [`skills.md`](skills.md) |
| `11_mcp_tool_sync.livemd` | MCP endpoints and prefixed sync | [`mcp-tools.md`](mcp-tools.md) |
| `12_web_tools.livemd` | Search/read web tools and safety checks | [`web-access.md`](web-access.md) |
| `13_plugins.livemd` | Plugin-published tool registries | [`plugins.md`](plugins.md) |
| `14_ash_resources.livemd` | Ash resource tools and actor checks | [`ash-resources.md`](ash-resources.md) |
| `15_imported_agents_deep_dive.livemd` | JSON/YAML imported agents | [`imported-agents.md`](imported-agents.md) |
| `16_workflow_patterns.livemd` | Function steps, refs, debug output | [`workflows.md`](workflows.md) |
| `17_evals.livemd` | Deterministic and provider-backed evals | [`evals.md`](evals.md) |
| `18_phoenix_liveview_consumer.livemd` | `Jidoka.AgentView` LiveView boundary | [`phoenix-liveview.md`](phoenix-liveview.md) |
| `19_production_checklist.livemd` | Pre-flight checks for shipping | [`production.md`](production.md) |
| `20_kitchen_sink.livemd` | Capstone composing many features | [`examples.md`](examples.md) |
| `21_structured_output.livemd` | Typed agent output, validation, repair | [`structured-output.md`](structured-output.md) |

Reading order, grouped by guide tier:

- Tier 0 to 1, foundations: `01`, `02`.
- Tier 2, orchestration and ops basics: `03`, `04`.
- Tier 3, lifecycle: `05`, `06`, `07`.
- Tier 4, per-capability deep dives: `08` through `14`.
- Imports parity: `15`.
- Workflow patterns: `16`.
- Operations and capstone: `17`, `18`, `19`, `20`.
- Structured output: `21`.

Session addressing is woven into the notebooks that need stable conversation
identity: tools/context, memory, handoffs, AgentView/Phoenix, production, and
the kitchen-sink capstone.

## Kino helpers

The `Jidoka.Kino` module is the public surface for Livebook helpers. It
provides a small, stable set of functions:

- `Jidoka.Kino.setup/1`: prepare the runtime once per notebook.
- `Jidoka.Kino.start_or_reuse/2`: stable agent IDs across cell re-runs.
- `Jidoka.Kino.chat/3`: run a chat call and render the result with a useful
  trace tab.
- `Jidoka.Kino.context/3`, `Jidoka.Kino.debug_agent/2`,
  `Jidoka.Kino.agent_diagram/2`: deterministic inspection.
- `Jidoka.Kino.timeline/2`, `Jidoka.Kino.call_graph/2`,
  `Jidoka.Kino.trace_table/2`: trace visualization.
- `Jidoka.Kino.compaction/2`: latest compaction snapshot visualization.
- `Jidoka.Kino.table/3`: small Markdown tables.

For the underlying trace data and the non-Livebook view, see
[`tracing.md`](tracing.md).

## Notebooks vs Mix demos

Notebooks and `mix jidoka <name>` demos cover overlapping ground but serve
different roles:

- Notebooks: interactive and explanatory. Each cell narrates a step, prints
  inspection output, and lets you tweak code in place. Best for learning and
  for sharing a runnable explanation.
- Mix demos: scripted and `--dry-run`-friendly. They run end-to-end from the
  terminal, are easy to wire into CI, and are the preferred shape for
  reproducing a scenario or smoke-testing a release.

Use a notebook when you want to understand a feature, and a demo when you
want to run one. See [`mix-tasks.md`](mix-tasks.md) for the demo catalog.

## See also

- [`getting-started.md`](getting-started.md)
- [`mix-tasks.md`](mix-tasks.md)
- [`tracing.md`](tracing.md)
- [`examples.md`](examples.md)
- [`imported-agents.md`](imported-agents.md)

## Imported agents

Imported JSON/YAML agents are first-class in the Livebook series: notebook
[`15_imported_agents_deep_dive.livemd`](https://github.com/agentjido/jidoka/blob/main/livebook/15_imported_agents_deep_dive.livemd)
covers explicit registries, provider rebinding, and capability parity with the
Elixir DSL. See [`imported-agents.md`](imported-agents.md) for the written
companion.
