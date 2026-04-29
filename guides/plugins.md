# Plugins

A Jidoka plugin packages a related set of tools (and supporting state)
behind one stable name. Use a plugin when you have several tools that
belong together, want to share them across agents, or want to publish a
tool bundle to other applications without forcing each consumer to wire up
every tool individually.

## Minimal Example

Define the plugin:

```elixir
defmodule MyApp.Plugins.Math do
  use Jidoka.Plugin,
    description: "Provides extra math tools.",
    tools: [MyApp.Tools.AddNumbers, MyApp.Tools.MultiplyNumbers]
end
```

Attach it to an agent:

```elixir
capabilities do
  plugin MyApp.Plugins.Math
end
```

The plugin's tools merge into the agent's tool registry alongside direct
tools, Ash actions, MCP tools, web tools, and skill tools.

## Authoring A Plugin

`use Jidoka.Plugin` accepts:

- `description`: required string describing what the plugin provides.
- `tools`: list of action-backed tool modules (typically modules that
  `use Jidoka.Tool`).
- `name`: optional explicit published plugin name. Defaults to the
  underscored module suffix, so `MyApp.Plugins.Math` publishes as
  `"math"`.

Plugin tool names must be unique inside the plugin; the compiler rejects
duplicates as part of plugin compilation.

## How Plugin Tools Reach The Agent

When you list `plugin MyApp.Plugins.Math`, Jidoka:

- Validates the plugin module exposes the required Jido.Plugin contract.
- Reads the plugin's published name and tool list.
- Merges every plugin-provided tool into the agent's tool registry.
- Rejects compilation if a plugin tool collides with a direct tool, Ash
  action, MCP tool, web tool, or skill tool name.

From the model's point of view there is no difference between a tool
attached with `tool` and one attached through `plugin`. They share the
same input contract and the same `run/2` callback. See
[tools.md](./tools.md) for the tool authoring details.

## Composing Multiple Plugins

```elixir
capabilities do
  plugin MyApp.Plugins.Math
  plugin MyApp.Plugins.Support
  tool MyApp.Tools.LookupOrder
end
```

Plugin names must also be unique across the agent. If two plugins publish
the same tool name, rename the tool in one of them or wrap it in a new
plugin.

## See Also

- [tools.md](./tools.md)
- [ash-resources.md](./ash-resources.md)
- [skills.md](./skills.md)
- [agents.md](./agents.md)
- [errors.md](./errors.md)

## Imported Agents

Imported specs reference plugins by published name and resolve them
through the `available_plugins:` registry on `Jidoka.import_agent/2`:

```elixir
Jidoka.import_agent(json, available_plugins: [MyApp.Plugins.Math])
```

```json
{
  "capabilities": {
    "plugins": ["math"]
  }
}
```

Raw module strings are rejected so imported agents cannot bypass the
application allowlist. See [imported-agents.md](./imported-agents.md).
