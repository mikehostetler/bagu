# Moto

Minimal layer over Jido and Jido.AI for defining and starting chat agents.

This first implementation keeps the Spark DSL deliberately tiny.

## Overview

Moto currently gives you a narrow, developer-friendly way to build chat-style
LLM agents on top of Jido and Jido.AI.

Today, Moto can:

- define agents with a small Spark DSL via `use Moto.Agent`
- configure agent `name`, `model`, `system_prompt`, `tools`, and `plugins`
- resolve models through Moto-owned aliases like `:fast`, direct model strings,
  inline maps, and `%LLMDB.Model{}`
- support static or dynamic system prompts through strings, module callbacks,
  and MFA tuples
- define tools with `use Moto.Tool` as a thin, Zoi-only wrapper over `Jido.Action`
- attach tools directly or expose all generated `AshJido` actions for an Ash
  resource with `ash_resource`
- define plugins with `use Moto.Plugin` and let them contribute tools into the
  agent's visible tool registry
- start many runtime instances from the same agent module under the shared
  `Moto.Runtime`
- import constrained agents from JSON or YAML at runtime with explicit
  allowlists for tools and plugins
- run local demo scripts that exercise full LLM + tool-call loops

Moto is intentionally opinionated. It keeps the public surface focused on
common agent authoring and hides most low-level Jido runtime machinery by
default.

## Setup

Set your Anthropic API key:

```bash
export ANTHROPIC_API_KEY=sk-ant-...
```

Or copy `.env.example` to `.env` and fill in the key.

`moto` uses `dotenvy` in `config/runtime.exs` to load `.env` automatically at
runtime. Shell environment variables still win over `.env` values.

`moto` owns its model aliases under `config :moto, :model_aliases`.
By default, `:fast` maps to `anthropic:claude-haiku-4-5`.

The generated runtime currently uses:

- the DSL-configured `model` value, defaulting to `:fast`
- the DSL-configured `tools`
- the DSL-configured `plugins`

Model configuration lives in:

- `config/config.exs` maps `:fast` under `config :moto, :model_aliases`
- `config/runtime.exs` loads `.env` and configures `:req_llm`

## Define An Agent

```elixir
defmodule MyApp.ChatAgent do
  use Moto.Agent

  agent do
    model :fast
    system_prompt "You are a concise assistant."
  end
end
```

The DSL currently supports:

- `name`
- `model`
- `system_prompt`
- `tools`
- `plugins`

`model` accepts the same shapes Jido.AI and ReqLLM support:

- alias atoms like `:fast`
- direct model strings like `"anthropic:claude-haiku-4-5"`
- inline maps like `%{provider: :anthropic, id: "claude-haiku-4-5"}`
- `%LLMDB.Model{}` structs

Example with all three:

```elixir
defmodule MyApp.SupportAgent do
  use Moto.Agent

  agent do
    name "support"
    model "anthropic:claude-haiku-4-5"
    system_prompt "You help customers with support questions."
  end
end
```

`system_prompt` supports three forms:

- a static string
- a module implementing `resolve_system_prompt/1`
- an MFA tuple like `{MyApp.SupportPrompt, :build, ["prefix"]}`

Module-based dynamic prompt:

```elixir
defmodule MyApp.SupportPrompt do
  @behaviour Moto.Agent.SystemPrompt

  @impl true
  def resolve_system_prompt(%{context: context}) do
    tenant = Map.get(context, :tenant, "unknown")
    "You help support users for tenant #{tenant}."
  end
end

defmodule MyApp.SupportAgent do
  use Moto.Agent

  agent do
    model :fast
    system_prompt MyApp.SupportPrompt
  end
end
```

MFA-based dynamic prompt:

```elixir
defmodule MyApp.SupportPrompts do
  def build(%{context: context}, prefix) do
    tenant = Map.get(context, :tenant, "unknown")
    {:ok, "#{prefix} #{tenant}."}
  end
end

defmodule MyApp.SupportAgent do
  use Moto.Agent

  agent do
    model :fast
    system_prompt {MyApp.SupportPrompts, :build, ["Support tenant"]}
  end
end
```

Dynamic system prompts resolve once per turn through Jido.AI's request
transformer hook, using the current runtime context.

## Define A Tool

```elixir
defmodule MyApp.Tools.AddNumbers do
  use Moto.Tool,
    description: "Adds two integers together.",
    schema: Zoi.object(%{a: Zoi.integer(), b: Zoi.integer()})

  @impl true
  def run(%{a: a, b: b}, _context) do
    {:ok, %{sum: a + b}}
  end
end
```

`Moto.Tool` is a thin wrapper over `Jido.Action`. It defaults the published
tool name from the module name and keeps the runtime contract as a plain Jido
action module.

Moto tools are Zoi-only for `schema` and `output_schema`. NimbleOptions and raw
JSON Schema maps are intentionally not supported through the Moto API.

## Attach Tools To An Agent

```elixir
defmodule MyApp.MathAgent do
  use Moto.Agent

  agent do
    model :fast
    system_prompt "You can use math tools."
  end

  tools do
    tool MyApp.Tools.AddNumbers
  end
end
```

You can also expose all generated `AshJido` actions for a resource:

```elixir
defmodule MyApp.UserAgent do
  use Moto.Agent

  agent do
    model :fast
    system_prompt "You can use account tools."
  end

  tools do
    ash_resource MyApp.Accounts.User
  end
end
```

For `ash_resource` tools, Moto will:

- expand the resource into its generated `AshJido` action modules
- inject the resource's Ash domain into `tool_context`
- require an explicit `tool_context.actor` on `MyApp.UserAgent.chat/3`

Example:

```elixir
{:ok, pid} = MyApp.UserAgent.start_link(id: "user-agent")

{:ok, reply} =
  MyApp.UserAgent.chat(pid, "List users.", tool_context: %{actor: current_user})
```

## Define A Plugin

```elixir
defmodule MyApp.Plugins.Math do
  use Moto.Plugin,
    description: "Provides extra math tools.",
    tools: [MyApp.Tools.MultiplyNumbers]
end
```

`Moto.Plugin` is a thin wrapper over `Jido.Plugin`. In this first pass, the
Moto-facing plugin contract is intentionally small:

- publish a stable plugin name
- register action-backed tools
- let Moto merge those tools into the agent's LLM-visible tool registry

## Attach Plugins To An Agent

```elixir
defmodule MyApp.MathAgent do
  use Moto.Agent

  agent do
    model :fast
    system_prompt "You can use math tools."
  end

  plugins do
    plugin MyApp.Plugins.Math
  end
end
```

Plugin-provided tools are merged into `MyApp.MathAgent.tools/0` and exposed to
the underlying Jido.AI runtime just like tools registered directly in the
`tools do ... end` block.

## Start And Chat

```elixir
{:ok, pid} = MyApp.ChatAgent.start_link(id: "chat-1")
{:ok, reply} = MyApp.ChatAgent.chat(pid, "Write a one-line haiku about Elixir.")
```

Or through the top-level Moto runtime facade:

```elixir
{:ok, pid} = MyApp.ChatAgent.start_link(id: "chat-1")
{:ok, reply} = Moto.chat(pid, "Write a one-line haiku about Elixir.")
```

Or use the shared runtime facade directly:

```elixir
{:ok, pid} = Moto.start_agent(MyApp.ChatAgent.runtime_module(), id: "chat-2")
{:ok, reply} = MyApp.ChatAgent.chat(pid, "Say hello.")
```

## Demo Script

Interactive:

```bash
mix run scripts/chat_agent.exs
```

By default, the script runs one built-in tool-call demo first, then drops into
interactive mode. You should see a line like `[tool:add_numbers] 17 + 25 = 42`
when the tool executes.

One-shot:

```bash
mix run scripts/chat_agent.exs -- "Use the add_numbers tool to add 17 and 25. Reply with only the sum."
```

Imported JSON agent:

```bash
mix run scripts/imported_chat_agent.exs
mix run scripts/imported_chat_agent.exs -- "Use the add_numbers tool to add 17 and 25. Reply with only the sum."
```

The sample imported agent spec lives at `priv/moto/sample_math_agent.json`.

## Dynamic Import

Moto also supports a constrained runtime import path for the same minimal agent
shape.

JSON:

```elixir
json = ~S"""
{
  "name": "json_agent",
  "model": "fast",
  "system_prompt": "You are a concise assistant.",
  "plugins": ["math_plugin"]
}
"""

{:ok, agent} =
  Moto.import_agent(
    json,
    available_plugins: [MyApp.Plugins.Math]
  )

{:ok, pid} = Moto.start_agent(agent, id: "json-agent")
{:ok, reply} = Moto.chat(pid, "Say hello.")
```

YAML:

```elixir
yaml = """
name: "yaml_agent"
model:
  provider: "openai"
  id: "gpt-4.1"
system_prompt: |-
  You are a concise assistant.
plugins:
  - "math_plugin"
"""

{:ok, agent} = Moto.import_agent(yaml,
  format: :yaml,
  available_plugins: [MyApp.Plugins.Math]
)
```

The dynamic import path is intentionally narrower than the Elixir DSL:

- only `name`
- only `model`
- only `system_prompt`
- only published tool names through `tools`
- only published plugin names through `plugins`
- `model` supports:
  - alias strings like `"fast"`
  - direct model strings like `"anthropic:claude-haiku-4-5"`
  - inline maps like `%{"provider" => "openai", "id" => "gpt-4.1"}`
- `tools` supports:
  - string names like `["add_numbers"]`
  - explicit resolution through `available_tools: [MyApp.Tools.AddNumbers]`
  - action-backed tool modules, including generated `AshJido` actions
- `plugins` supports:
  - string names like `["math_plugin"]`
  - explicit resolution through `available_plugins: [MyApp.Plugins.Math]`

The imported path does not currently support the `ash_resource` shorthand
directly, because JSON/YAML specs cannot safely encode Elixir resource modules.
It also does not support dynamic `system_prompt` callbacks yet, because the
constrained JSON/YAML format intentionally avoids executable Elixir references.

The top-level helpers are:

- `Moto.import_agent/2`
- `Moto.import_agent_file/2`
- `Moto.encode_agent/2`
- `Moto.chat/3`

## Notes

- The shared runtime lives in `Moto.Runtime` and is started by `Moto.Application`.
- `Moto.Agent` uses a very small Spark DSL and generates a nested runtime module.
- `Moto.Tool` is a thin wrapper over `Jido.Action`, but it restricts tool schemas to Zoi.
- `Moto.Plugin` is a thin wrapper over `Jido.Plugin` and currently focuses on contributing tools.
- `Moto.model/1` resolves Moto-owned aliases first, then delegates to Jido.AI.
- Dynamic imports use a hidden runtime module generated from a validated Zoi spec.
- Imported tools and plugins are constrained to explicit allowlist registries.
- The nested runtime module still uses `Jido.AI.Agent` underneath.
