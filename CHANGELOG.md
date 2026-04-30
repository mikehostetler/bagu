# Changelog

All notable changes to Jidoka will be documented in this file.

This project follows conventional commits. Beta releases are intended for early
adopters while the public API is still allowed to change before a stable 1.0.

## 1.0.0-beta.1 - 2026-04-30

### Added

- Spark-backed `Jidoka.Agent` DSL for chat-oriented Jido/Jido.AI agents.
- Jidoka-native tools, plugins, hooks, guardrails, runtime context, memory, skills,
  MCP tools, and manager-pattern subagents.
- Imported JSON/YAML agent specs with explicit registries.
- First-class structured output with Zoi schemas, validation, repair attempts,
  and imported-agent JSON/YAML support.
- First-class bounded run tracing with timeline, table, and call-graph helpers.
- Canonical provider-free examples for support triage, lead qualification, data
  analysis, meeting follow-up, feedback synthesis, invoice extraction, incident
  triage, approval flows, PR review, research briefs, and document intake.
- Livebook tutorials covering the core feature set, plus an advanced
  kitchen-sink notebook.
- Demo Mix task with chat, orchestrator, imported-agent, and kitchen-sink modes.

### Changed

- Refactored agent compilation, subagent runtime, imported-agent handling, and
  demo CLI internals into smaller single-purpose modules.
- Prepared Hex package metadata and documentation for the first public beta.

### Notes

- Jidoka remains beta software. Pin exact versions for production experiments
  and expect small breaking changes before stable 1.0.
