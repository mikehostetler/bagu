# Instructions

`defaults.instructions` is the system prompt that Jidoka maps onto the
underlying Jido.AI machinery. Compiled agents accept three forms: a static
string, a module that implements the `Jidoka.Agent.SystemPrompt` behaviour, or
an MFA tuple. Module and MFA forms are dynamic: they resolve once per turn
using the parsed runtime context.

## Static string

The simplest form. Use this when the prompt does not depend on per-turn data:

```elixir
defaults do
  instructions "You are concise and direct."
end
```

The string must be non-empty. Jidoka validates this at compile time.

## Module resolver

Implement `Jidoka.Agent.SystemPrompt` and pass the module:

```elixir
defmodule MyApp.SupportPrompt do
  @behaviour Jidoka.Agent.SystemPrompt

  @impl true
  def resolve_system_prompt(%{context: context}) do
    tenant = Map.get(context, :tenant, "unknown")
    "You help support users for tenant #{tenant}."
  end
end

defaults do
  instructions MyApp.SupportPrompt
end
```

The callback receives a map with `:request`, `:state`, `:config`, and
`:context` keys. It must return either a non-empty `String.t()`, `{:ok,
String.t()}`, or `{:error, reason}`.

## MFA resolver

Use a `{module, function, args}` tuple when you want to share a resolver across
agents and pass extra static arguments:

```elixir
defaults do
  instructions {MyApp.SupportPrompts, :build, ["Support tenant"]}
end
```

The function is invoked as `MyApp.SupportPrompts.build(input, "Support tenant")`,
where `input` is the same map the module callback receives. Jidoka verifies the
target arity at compile time.

## Dynamic resolution per turn

Module and MFA resolvers run on every chat turn, after Jidoka parses the
incoming `context:` through the agent's compiled schema. This is the most
direct way to make selected context visible to the model. For example, a
resolver can read `context.account_id` and weave it into the prompt without
exposing the full context map.

Resolution happens once per turn, before tools or memory run. If the resolver
raises or returns an unexpected shape, Jidoka surfaces a
`Jidoka.Error.ExecutionError` through the standard return shapes.

## Interaction with characters

Characters (see [characters.md](characters.md)) render persona text into the
final system prompt alongside the resolved instructions. Instructions resolve
first, then character rendering composes the complete prompt.

## See also

- [agents.md](agents.md): where `defaults.instructions` sits in the DSL.
- [context.md](context.md): how per-turn context becomes the `:context` field
  passed to dynamic resolvers.
- [characters.md](characters.md): persona data that composes with instructions.
- [chat-turn.md](chat-turn.md): where instruction resolution fits in the turn
  lifecycle.
- [errors.md](errors.md): error classes returned when a resolver fails.

## Imported agents

Imported JSON and YAML agents accept `defaults.instructions` as a static
string only. Module callbacks and MFA tuples are compile-only features (they
require code that the import format cannot reference safely). When you need
per-turn dynamic prompts in an imported agent, project context through hooks,
memory, or tool descriptions instead. See
[imported-agents.md](imported-agents.md).
