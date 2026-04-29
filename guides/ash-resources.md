# Ash Resources

The `ash_resource` capability turns an Ash resource into a set of agent
tools by expanding the resource's `AshJido` actions. Use it when the agent
should read or write through Ash rather than through hand-written tools.
This keeps authorization, validation, and persistence in Ash where they
belong.

## Minimal Example

```elixir
defmodule MyApp.UserAgent do
  use Jidoka.Agent

  agent do
    id "user_agent"
  end

  defaults do
    instructions "You manage user accounts using the provided tools."
  end

  capabilities do
    ash_resource MyApp.Accounts.User
  end
end
```

The resource must already be extended with `AshJido` and expose at least
one action through a `jido do ... end` block.

## What `ash_resource` Does

For every entry, Jidoka:

- Validates the module is an Ash resource and has a domain.
- Expands the resource into the generated `AshJido` action modules.
- Publishes each action as a tool using its `AshJido` name.
- Injects the resource's domain into the runtime context so actions can
  resolve relationships and policies.

All `ash_resource` entries on a single agent must share the same Ash
domain. Mixing domains is rejected at compile time.

## The `context.actor` Requirement

Ash actions usually run on behalf of a user. Jidoka enforces this for
`ash_resource` tools by requiring an `actor` in the per-turn context:

```elixir
{:ok, reply} =
  MyApp.UserAgent.chat(pid, "List the most recent users.",
    context: %{actor: current_user}
  )
```

Without `context.actor`, the chat turn returns a
`%Jidoka.Error.ValidationError{}` before the model is invoked.

For details on how context is merged across defaults, agent state, and
per-turn calls, see [context.md](./context.md).

## Mixing With Direct Tools

Ash-generated tools share the same registry as direct tools, plugins, MCP
endpoints, web tools, and skill tools:

```elixir
capabilities do
  ash_resource MyApp.Accounts.User
  tool MyApp.Tools.SendInvite
end
```

If two sources publish the same name, compilation fails. Rename one of
them or pick a different action name in the resource's `jido do` block.

## See Also

- [tools.md](./tools.md)
- [context.md](./context.md)
- [agents.md](./agents.md)
- [errors.md](./errors.md)
- [plugins.md](./plugins.md)

## Imported Agents

Imported specs reference tool names, not Elixir module strings. To make
Ash-generated tools available to a JSON/YAML agent, expand the resource in
your application code and pass the resulting action modules through
`available_tools:`:

```elixir
modules = AshJido.Tools.actions(MyApp.Accounts.User)

Jidoka.import_agent(json,
  available_tools: modules,
  # ...
)
```

The imported spec then lists the same action names under
`capabilities.tools`, and `context.actor` is still required at chat time.
See [imported-agents.md](./imported-agents.md).
