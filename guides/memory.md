# Memory

Jidoka memory is lifecycle policy. It is configured in `lifecycle do`, not in
`capabilities do`, because memory changes how a turn is prepared rather than
adding a model-callable tool.

Jidoka uses `jido_memory` underneath and keeps the public DSL small.

## Basic Memory

```elixir
defmodule MyApp.ChatAgent do
  use Jidoka.Agent

  agent do
    id :chat_agent

    schema Zoi.object(%{
      session: Zoi.string(),
      tenant: Zoi.string() |> Zoi.default("demo")
    })
  end

  defaults do
    model :fast
    instructions "You are a concise assistant."
  end

  lifecycle do
    memory do
      mode :conversation
      namespace {:context, :session}
      capture :conversation
      retrieve limit: 5
      inject :instructions
    end
  end
end
```

This retrieves up to five records for the current session, injects them into
instructions, and captures conversation turns back into memory.

## Supported Settings

Memory mode:

```elixir
mode :conversation
```

Namespace:

```elixir
namespace :per_agent
namespace :shared
namespace {:context, :session}
```

Shared namespace:

```elixir
namespace :shared
shared_namespace "support"
```

Capture:

```elixir
capture :conversation
capture :off
```

Retrieve:

```elixir
retrieve limit: 5
```

Inject:

```elixir
inject :instructions
inject :context
```

## Namespace Rules

Use `:per_agent` when each agent should have isolated memory.

Use `:shared` with `shared_namespace` when multiple agents should share the same
memory space:

```elixir
memory do
  mode :conversation
  namespace :shared
  shared_namespace "support"
end
```

Use `{:context, key}` when memory should partition by runtime context:

```elixir
memory do
  mode :conversation
  namespace {:context, :session}
end
```

When the agent has a schema, Jidoka validates that `key` exists in the schema.
See [Context](context.html) for how the compiled context schema is declared.

## Injection Modes

`inject :instructions` appends a bounded `Relevant memory:` section to the
effective instructions for the turn. This makes retrieved memory visible to the
model.

`inject :context` places retrieved records into runtime context for hooks,
tools, and plugins. It does not automatically expose memory to the model.

Choose `:instructions` for ordinary chat memory. Choose `:context` when app code
should inspect memory before deciding what to reveal.

## Runtime Error Policy

Memory retrieval failures are hard execution errors because the turn cannot be
prepared as configured.

Capture/write failures are treated as soft structured warnings in debug/request
metadata. The user should still receive the model response when only capture
fails.

Use `Jidoka.inspect_request/1` when debugging memory behavior in a live turn.

## Imported Agents

Imported JSON/YAML agents have parity here: they configure the same memory
behavior through the constrained `lifecycle.memory` block. See
[Imported Agents](imported-agents.html) for the full spec.

```json
{
  "lifecycle": {
    "memory": {
      "mode": "conversation",
      "namespace": "context",
      "context_namespace_key": "session",
      "capture": "conversation",
      "retrieve": {"limit": 5},
      "inject": "instructions"
    }
  }
}
```

Imported agents do not support portable Zoi schemas yet, so context namespace
keys are validated against runtime context/defaults rather than a compiled
schema.

## When Not To Use Memory

Do not use memory for facts the application should authoritatively query from a
database. Use a tool for that.

Do not use memory for secrets or authorization state. Keep those in runtime
context and tools.

Do not use memory to hide unclear product behavior. If the agent needs a stable
process, use a workflow.
