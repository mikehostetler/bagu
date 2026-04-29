# MCP Tools

The `mcp_tools` capability exposes tools that live behind a Model Context
Protocol (MCP) endpoint. Use it when the tools are owned by an external
process or service (for example, a GitHub MCP server) and should be synced
into the agent's tool registry at runtime.

## Minimal Example

```elixir
capabilities do
  mcp_tools endpoint: :github, prefix: "github_"
end
```

On the first chat turn, Jidoka resolves the endpoint, syncs its tools into
the agent, and prefixes every published tool name with `"github_"` so they
do not collide with other capabilities.

## Endpoint Sources

Endpoints can come from three places:

- App config: registered through `:jido_mcp` application configuration on
  boot.
- Runtime registration: registered with `Jido.MCP.register_endpoint/1`
  before the agent is started.
- Inline DSL: registered automatically when the `mcp_tools` entry includes
  a `transport:` definition.

The compiled DSL accepts:

```elixir
capabilities do
  mcp_tools endpoint: :local_tools,
    prefix: "local_",
    transport: %{type: :stdio, command: "my_mcp_server"},
    client_info: %{name: "jidoka"}
end
```

When `transport:` is present, Jidoka calls into `jido_mcp` to ensure the
endpoint exists, treating matching definitions as idempotent and surfacing
mismatched definitions as errors.

## Naming And Conflicts

Each MCP entry publishes one tool per remote tool, optionally prefixed.
These names join the same registry as direct tools, plugins, web tools,
Ash-generated tools, and skill tools. If two sources publish the same
name, compilation fails. Resolve conflicts by changing `prefix:` or
renaming the upstream tool.

## Security Posture

MCP transports talk to external processes or services. Jidoka keeps that
configuration in application code on purpose:

- The compiled DSL can declare a transport because the module owner has
  full control over what gets registered.
- Imported JSON/YAML specs cannot declare a transport. They reference
  endpoints by id only, and the application is responsible for
  registering them.

This keeps credentials and command lines out of portable agent specs.

## See Also

- [tools.md](./tools.md)
- [plugins.md](./plugins.md)
- [web-access.md](./web-access.md)
- [agents.md](./agents.md)
- [errors.md](./errors.md)

## Imported Agents

Imported specs list MCP capabilities by endpoint id and optional prefix:

```json
{
  "capabilities": {
    "mcp_tools": [
      {"endpoint": "github", "prefix": "github_"}
    ]
  }
}
```

The endpoint must already be registered with `jido_mcp` (through app
config or runtime registration) before the imported agent runs. Inline
transport definitions are intentionally not supported in imported specs.
See [imported-agents.md](./imported-agents.md).
