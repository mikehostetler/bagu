# AGENTS.md - Moto Package Guide

## Intent

This directory contains the `moto` Elixir package.

`moto` is a thin, opinionated layer over Jido and Jido.AI for building
developer-friendly LLM agents with a narrow public API.

The package currently has two public authoring paths:

- the compile-time Elixir DSL via `use Moto.Agent`
- the runtime import path for constrained JSON/YAML agent specs

Both paths describe the same conceptual Moto agent.

## Working Rules

- Prefer changes in this package over changes in vendored dependencies.
- Keep the public Moto API small, explicit, and biased toward common agent use
  cases.
- Hide low-level Jido/Jido.AI concepts by default unless there is a clear DX
  reason to expose them.
- Favor compile-time validation for the Elixir DSL and strong runtime
  validation for imported specs.

## Parity Rule

Imported agents are not a side path. They are a first-class Moto surface.

When adding a new public Moto agent feature, evaluate both authoring paths at
the same time:

- `Moto.Agent` should gain the feature in the Elixir DSL when appropriate.
- imported JSON/YAML agents should gain the same feature when it can be
  represented safely in the constrained spec format.
- if the imported-agent path cannot support the feature yet, document that gap
  explicitly in code, tests, and README instead of letting the APIs drift
  silently.

The goal is feature parity by default, with intentional exceptions rather than
accidental divergence.

## Current Scope

Right now the shared public agent shape is intentionally minimal:

- `name`
- `model`
- `system_prompt`
- `tools`
- `plugins`

The Elixir DSL may expose richer compile-time ergonomics, but the imported
agent format should stay aligned on capability as features are added.

## Commands

Run package commands from this directory:

- `mix deps.get`
- `mix compile`
- `mix test`
- `mix format`

## References

- [/Users/mhostetler/Source/Moto/AGENTS.md](/Users/mhostetler/Source/Moto/AGENTS.md:1)
- [README.md](/Users/mhostetler/Source/Moto/moto/README.md:1)
- [TODO.md](/Users/mhostetler/Source/Moto/moto/TODO.md:1)
