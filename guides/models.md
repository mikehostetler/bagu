# Models

`defaults.model` selects the LLM that an agent talks to. Jidoka accepts the
same model inputs Jido.AI does, plus a Jidoka-level alias map. Use aliases for
application-wide defaults and explicit strings or maps when an agent needs a
specific provider and id.

## Minimal example

```elixir
defmodule MyApp.SupportAgent do
  use Jidoka.Agent

  agent do
    id :support_agent
  end

  defaults do
    model :fast
    instructions "You help customers with support questions."
  end
end
```

If `defaults.model` is omitted, Jidoka uses `:fast`.

## Accepted forms

`defaults.model` accepts:

- alias atoms: `:fast`, `:smart`, or any key you register.
- direct strings: `"anthropic:claude-haiku-4-5"`, `"openai:gpt-4o-mini"`.
- inline maps: `%{provider: :anthropic, id: "claude-haiku-4-5"}`.
- `%LLMDB.Model{}` structs returned by `LLMDB.model/1`, `LLMDB.model/2`,
  and friends.

Jidoka resolves the value at compile time so that `MyApp.SupportAgent.model/0`
returns the resolved struct.

## Alias atoms

Atoms are looked up against the merged alias maps from Jidoka and Jido.AI.
Jido.AI ships a set of curated aliases (such as `:fast`); Jidoka adds an
application-level layer on top:

```elixir
# config/config.exs
config :jidoka, :model_aliases, %{
  default_chat: "anthropic:claude-haiku-4-5",
  cheap: %{provider: :openai, id: "gpt-4o-mini"}
}
```

```elixir
defaults do
  model :default_chat
end
```

Application aliases win over Jido.AI defaults when the keys collide. Use this
to centralize provider choices for a deployment.

## Direct strings

Use a `"provider:id"` string when an agent needs an explicit pair and you do
not want to introduce an alias:

```elixir
defaults do
  model "anthropic:claude-haiku-4-5"
end
```

## Inline maps

Maps are useful when you need to override `base_url` for a self-hosted gateway
or local proxy:

```elixir
defaults do
  model %{
    provider: :openai,
    id: "gpt-4o-mini",
    base_url: "https://gateway.example.com/v1"
  }
end
```

## Pre-resolved structs

When you already hold a `%LLMDB.Model{}` (for example from a registry lookup)
you can pass it through directly. Jidoka treats it as resolved and skips
further lookup.

## Runtime resolution helper

`Jidoka.model/1` resolves any of the accepted inputs at runtime. Use it from
configuration loaders, REPL sessions, or tests when you want a struct without
booting an agent:

```elixir
{:ok, model} = Jidoka.model(:fast)
{:ok, model} = Jidoka.model("anthropic:claude-haiku-4-5")
```

## Application defaults vs per-agent override

The recommended pattern is:

1. Define a small set of named aliases in `config :jidoka, :model_aliases`.
2. Have most agents declare `model :default_chat` (or similar).
3. Override on individual agents only when a specific model is required.

That keeps provider choices in one place and makes per-environment swaps
(staging vs production) a config edit rather than a code change.

## See also

- [agents.md](agents.md): where `defaults.model` sits in the DSL.
- [getting-started.md](getting-started.md): first-run model setup.
- [overview.md](overview.md): how Jidoka layers on top of Jido.AI.
- [chat-turn.md](chat-turn.md): when the model is invoked during a turn.
- [production.md](production.md): operational guidance for model selection.

## Imported agents

Imported JSON and YAML agents accept the alias string form (for example
`"fast"`), direct provider strings (`"anthropic:claude-haiku-4-5"`), and inline
maps with `provider`, `id`, and an optional `base_url`. Pre-resolved
`%LLMDB.Model{}` structs are not part of the import surface (they cannot be
serialized safely). See [imported-agents.md](imported-agents.md).
