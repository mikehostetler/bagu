# Tools

Tools are the deterministic application functions an agent can call. Use
`Jidoka.Tool` whenever the model needs a typed, predictable side effect:
looking up an order, computing a total, fetching a record, sending a
notification. Tools are the most common capability and the foundation that
plugins, Ash resources, MCP, web access, and skills all build on.

## Minimal Example

```elixir
defmodule MyApp.Tools.AddNumbers do
  use Jidoka.Tool,
    description: "Adds two integers together.",
    schema: Zoi.object(%{a: Zoi.integer(), b: Zoi.integer()}),
    output_schema: Zoi.object(%{sum: Zoi.integer()})

  @impl true
  def run(%{a: a, b: b}, _context) do
    {:ok, %{sum: a + b}}
  end
end
```

Attach the tool to an agent:

```elixir
defmodule MyApp.MathAgent do
  use Jidoka.Agent

  agent do
    id "math_agent"
  end

  defaults do
    instructions "You answer math questions using the provided tools."
  end

  capabilities do
    tool MyApp.Tools.AddNumbers
  end
end
```

## Authoring A Tool

`use Jidoka.Tool` accepts:

- `description`: required string the model sees alongside the tool name.
- `schema`: optional Zoi schema for input parameters.
- `output_schema`: optional Zoi schema for the value returned by `run/2`.
- `name`: optional explicit published name. Defaults to the underscored
  module suffix, so `MyApp.Tools.AddNumbers` publishes as `"add_numbers"`.

Jidoka tools are Zoi-only for `schema` and `output_schema`. The compiler
rejects any other schema format.

## The `run/2` Callback

```elixir
@spec run(map(), map()) ::
        {:ok, term()}
        | {:error, term()}
```

- The first argument is the validated, atom-keyed parameters.
- The second argument is the runtime context, including any
  `context:` map passed to `Jidoka.chat/3` and any defaults declared on
  the agent. See [context.md](./context.md).
- Return `{:ok, value}` on success. Jidoka serializes the value back to
  the model. If `output_schema` is set, the value is validated.
- Return `{:error, reason}` to surface a tool failure. The agent receives
  a structured error and can decide how to recover.

## Attaching Tools

Use the `tool` capability for direct tool modules:

```elixir
capabilities do
  tool MyApp.Tools.AddNumbers
  tool MyApp.Tools.LookupOrder
end
```

Tools also reach the agent indirectly through:

- [plugins.md](./plugins.md): packaged tool sets.
- [ash-resources.md](./ash-resources.md): generated AshJido actions.
- [mcp-tools.md](./mcp-tools.md): remote MCP endpoints.
- [skills.md](./skills.md): action-backed skill tools.
- [web-access.md](./web-access.md): built-in low-risk web tools.

All of these merge into the same per-agent tool registry.

## Name Conflicts

Each agent has one tool registry. Jidoka rejects duplicate published names
across direct tools, Ash-generated tools, MCP tools, skill tools, plugin
tools, and web tools at compile time. To resolve a clash, either rename the
tool with the `name:` option on `use Jidoka.Tool`, or rename one of the
upstream entries (for example, `mcp_tools prefix: "github_"`).

## See Also

- [getting-started.md](./getting-started.md)
- [agents.md](./agents.md)
- [context.md](./context.md)
- [structured-output.md](./structured-output.md)
- [plugins.md](./plugins.md)

## Imported Agents

Imported JSON/YAML specs reference tools by published name only. The
application supplies the executable modules through the
`available_tools:` registry on `Jidoka.import_agent/2`:

```elixir
Jidoka.import_agent(json, available_tools: [MyApp.Tools.AddNumbers])
```

Raw module strings are rejected so imported agents cannot bypass the
allowlist. See [imported-agents.md](./imported-agents.md).
