# Moto

Minimal layer over Jido and Jido.AI for defining and starting chat agents.

## Status

`moto` is currently an experimental spike only.

It is a design/prototyping repo, not a stable package. The API is expected to
change, large parts may be rewritten, and the repository may disappear entirely
if the spike does not hold up.

This first implementation keeps the Spark DSL deliberately tiny.

## Installation

Moto is not published to Hex yet. For local spike work, use the repository
directly:

```elixir
def deps do
  [
    {:moto, git: "https://github.com/mikehostetler/moto.git", branch: "main"}
  ]
end
```

When Moto is published, this section will be replaced with the Hex dependency
and any Igniter installer instructions.

## Overview

Moto currently gives you a narrow, developer-friendly way to build chat-style
LLM agents on top of Jido and Jido.AI.

Today, Moto can:

- define agents with a small Spark DSL via `use Moto.Agent`
- configure agent `name`, `model`, `system_prompt`, runtime context `schema`,
  `tools`, `memory`, `skills`, `plugins`, `hooks`, and `guardrails`
- resolve models through Moto-owned aliases like `:fast`, direct model strings,
  inline maps, and `%LLMDB.Model{}`
- support static or dynamic system prompts through strings, module callbacks,
  and MFA tuples
- define tools with `use Moto.Tool` as a thin, Zoi-only wrapper over `Jido.Action`
- compose prompt-level agent skills from Jido.AI skills, including runtime
  `SKILL.md` files
- sync remote MCP tool catalogs into an agent with `mcp_tools`
- attach tools directly or expose all generated `AshJido` actions for an Ash
  resource with `ash_resource`
- define plugins with `use Moto.Plugin` and let them contribute tools into the
  agent's visible tool registry
- define reusable `Moto.Hook` modules and attach them as default turn hooks or
  per-request overrides
- define reusable `Moto.Guardrail` modules and attach them as default
  input/output/tool validation stages or per-request overrides
- enable conversation-first memory with bounded retrieval and opt-in
  auto-capture on top of `jido_memory`
- start many runtime instances from the same agent module under the shared
  `Moto.Runtime`
- import constrained agents from JSON or YAML at runtime with explicit
  allowlists for tools, plugins, hooks, and guardrails, including default
  imported context and memory settings
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

For package development:

```bash
mix setup
mix test
mix quality
```

`mix quality` follows the Jido package quality baseline: formatting, compiler
warnings, Credo, Dialyzer, and documentation coverage.

Coverage is enforced with ExCoveralls at the current spike baseline of 70%.
The Jido package target is 90%; Moto should raise this before any stable
release instead of pretending the spike is already there.

The generated runtime currently uses:

- the DSL-configured `model` value, defaulting to `:fast`
- the DSL-configured context `schema`
- the DSL-configured `memory`
- the DSL-configured `skills`
- the DSL-configured `tools`
- the DSL-configured `plugins`
- the DSL-configured `hooks`

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

    schema Zoi.object(%{
      tenant: Zoi.string() |> Zoi.default("demo"),
      channel: Zoi.string() |> Zoi.default("web")
    })
  end
end
```

The DSL currently supports:

- `name`
- `model`
- `system_prompt`
- `schema`
- `memory`
- `skills`
- `tools`
- `plugins`
- `hooks`
- `guardrails`

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

## Default Context

Agents can define a runtime context schema directly in the `agent` block:

```elixir
defmodule MyApp.ChatAgent do
  use Moto.Agent

  agent do
    model :fast
    system_prompt "You are a concise assistant."

    schema Zoi.object(%{
      tenant: Zoi.string() |> Zoi.default("demo"),
      channel: Zoi.string() |> Zoi.default("web"),
      actor: Zoi.any() |> Zoi.optional(),
      order_id: Zoi.string() |> Zoi.optional()
    })
  end
end
```

Schema defaults are available through `MyApp.ChatAgent.context/0`. Per-turn
`context:` passed to `chat/3` is parsed through `MyApp.ChatAgent.context_schema/0`
before hooks, tools, guardrails, memory, and subagents see it.

## Memory

Moto memory is conversation-first and opt-in. It is implemented on top of
`jido_memory`, but Moto keeps the public surface narrow:

```elixir
defmodule MyApp.ChatAgent do
  use Moto.Agent

  agent do
    model :fast
    system_prompt "You are a concise assistant."
  end

  memory do
    mode :conversation
    namespace {:context, :session}
    capture :conversation
    retrieve limit: 5
    inject :system_prompt
  end
end
```

V1 memory supports only:

- `mode :conversation`
- `namespace :per_agent`
- `namespace :shared` with `shared_namespace "..."`
- `namespace {:context, key}`
- `capture :conversation` or `:off`
- `retrieve limit: n`
- `inject :system_prompt` or `:context`

`inject :system_prompt` appends a bounded `Relevant memory:` section to the
effective system prompt for the turn.

`inject :context` exposes retrieved records at `context.memory` for hooks,
tools, and plugins without automatically projecting memory into the prompt.

Memory is opt-in:

- no `memory do ... end` means no memory lifecycle at all
- `capture :off` disables writes but still allows retrieval from an existing
  namespace
- imported JSON/YAML agents support the same constrained memory subset

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
- inject the resource's Ash domain into the agent runtime context
- require an explicit `context.actor` on `MyApp.UserAgent.chat/3`

Example:

```elixir
{:ok, pid} = MyApp.UserAgent.start_link(id: "user-agent")

{:ok, reply} =
  MyApp.UserAgent.chat(pid, "List users.", context: %{actor: current_user})
```

## Attach Skills To An Agent

Moto skills are built on top of `Jido.AI.Skill`.

You can attach:

- module-based skills defined with `use Jido.AI.Skill`
- runtime-loaded `SKILL.md` files by published skill name plus `load_path`

```elixir
defmodule MyApp.MathAgent do
  use Moto.Agent

  agent do
    model :fast
    system_prompt "You are a concise assistant."
  end

  skills do
    skill "math-discipline"
    load_path "../skills"
  end
end
```

Moto uses skills in two ways:

- renders skill prompt text into the effective system prompt
- narrows the visible tool set when the skill declares `allowed-tools`

Module-based skills can also contribute action-backed tools through their
`actions:` list.

## Sync MCP Tools

Moto can sync remote MCP tools into the agent's tool registry:

```elixir
defmodule MyApp.GitHubAgent do
  use Moto.Agent

  agent do
    model :fast
    system_prompt "You can use GitHub MCP tools."
  end

  tools do
    mcp_tools endpoint: :github, prefix: "github_"
  end
end
```

Moto keeps MCP narrow in this first pass:

- MCP is treated as another tool source
- tools are synced before the model turn runs
- Moto does not currently expose raw MCP resources or prompts
- endpoint configuration still lives in `jido_mcp`

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

## Define A Hook

```elixir
defmodule MyApp.Hooks.ReplyWithFinalAnswer do
  use Moto.Hook, name: "reply_with_final_answer"

  @impl true
  def call(%Moto.Hooks.BeforeTurn{} = input) do
    {:ok, %{message: "#{input.message}\n\nReply with only the final answer."}}
  end
end
```

`Moto.Hook` is a thin wrapper for turn-scoped callouts. A hook publishes a
stable name and exposes a single `call/1` callback.

Moto currently supports three hook stages:

- `before_turn`
- `after_turn`
- `on_interrupt`

DSL hooks accept Moto hook modules or MFA tuples. Request-scoped `chat/3`
hooks also accept anonymous arity-1 functions.

## Attach Hooks To An Agent

```elixir
defmodule MyApp.ChatAgent do
  use Moto.Agent

  agent do
    model :fast
    system_prompt "You are a concise assistant."
  end

  hooks do
    before_turn MyApp.Hooks.ReplyWithFinalAnswer
    before_turn {MyApp.Hooks.AuditTurn, :call, [:support]}
    after_turn MyApp.Hooks.NormalizeReply
    on_interrupt MyApp.Hooks.NotifyOps
  end
end
```

Multiple hooks are allowed per stage. Moto stores them stage-by-stage and runs:

- `before_turn` hooks in declaration order
- `after_turn` hooks in reverse order
- `on_interrupt` hooks in reverse order

Generated agents expose:

- `MyApp.ChatAgent.hooks/0`
- `MyApp.ChatAgent.before_turn_hooks/0`
- `MyApp.ChatAgent.after_turn_hooks/0`
- `MyApp.ChatAgent.interrupt_hooks/0`

## Define A Guardrail

```elixir
defmodule MyApp.Guardrails.SafePrompt do
  use Moto.Guardrail, name: "safe_prompt"

  @impl true
  def call(%Moto.Guardrails.Input{message: message}) do
    if String.contains?(String.downcase(message), "secret") do
      {:error, :unsafe_prompt}
    else
      :ok
    end
  end
end
```

`Moto.Guardrail` is a thin wrapper for validation-only turn boundaries. A
guardrail publishes a stable name and exposes a single `call/1` callback.

Moto currently supports three guardrail stages:

- `input`
- `output`
- `tool`

Guardrails are non-mutating in v1. They can:

- allow the stage with `:ok`
- block the turn with `{:error, reason}`
- interrupt the turn with `{:interrupt, interrupt_like}`

Hooks remain the place for rewrites and enrichment.

## Attach Guardrails To An Agent

```elixir
defmodule MyApp.ChatAgent do
  use Moto.Agent

  agent do
    model :fast
    system_prompt "You are a concise assistant."
  end

  guardrails do
    input MyApp.Guardrails.SafePrompt
    output {MyApp.Guardrails.SafeReply, :call, [:support]}
    tool MyApp.Guardrails.ApproveRefundTool
  end
end
```

Multiple guardrails are allowed per stage. Moto runs them in declaration order
and short-circuits on the first block or interrupt.

Generated agents expose:

- `MyApp.ChatAgent.guardrails/0`
- `MyApp.ChatAgent.input_guardrails/0`
- `MyApp.ChatAgent.output_guardrails/0`
- `MyApp.ChatAgent.tool_guardrails/0`

Tool guardrails run at the model-selected tool-call boundary before execution.
They validate the proposed tool name, arguments, and runtime context, but they
do not control tool exposure and do not inspect tool results in v1.

## Per-Turn Hook Overrides

You can also pass hooks directly to `chat/3`:

```elixir
runtime_before_turn = fn %Moto.Hooks.BeforeTurn{} = input ->
  {:ok, %{context: Map.put(input.context, :tenant, "acme")}}
end

{:ok, pid} = MyApp.ChatAgent.start_link(id: "chat-1")

{:ok, reply} =
  MyApp.ChatAgent.chat(pid, "Say hello.",
    hooks: [
      before_turn: [
        MyApp.Hooks.ReplyWithFinalAnswer,
        {MyApp.Hooks.AuditTurn, :call, [:support]},
        runtime_before_turn
      ]
    ]
  )
```

`chat/3` hook overrides append to the agent's default DSL hooks for that turn.
If a hook interrupts the turn, Moto returns:

```elixir
{:interrupt, %Moto.Interrupt{}}
```

## Per-Turn Guardrail Overrides

You can also pass guardrails directly to `chat/3`:

```elixir
runtime_input_guardrail = fn %Moto.Guardrails.Input{} = input ->
  if Map.get(input.context, :tenant) == "blocked" do
    {:error, :blocked_tenant}
  else
    :ok
  end
end

{:ok, pid} = MyApp.ChatAgent.start_link(id: "chat-1")

{:ok, reply} =
  MyApp.ChatAgent.chat(pid, "Say hello.",
    guardrails: [
      input: [
        MyApp.Guardrails.SafePrompt,
        {MyApp.Guardrails.TenantGate, :call, [:support]},
        runtime_input_guardrail
      ]
    ]
  )
```

`chat/3` guardrail overrides append to the agent's default DSL guardrails for
that turn. When a guardrail blocks, Moto returns:

```elixir
{:error, {:guardrail, :input, "safe_prompt", :unsafe_prompt}}
```

When a guardrail interrupts, Moto returns:

```elixir
{:interrupt, %Moto.Interrupt{}}
```

## Runtime Context

Moto uses `context:` as the public name for request-scoped runtime data.

```elixir
{:ok, pid} = MyApp.ChatAgent.start_link(id: "chat-1")

{:ok, reply} =
  MyApp.ChatAgent.chat(pid, "Help with order 123",
    context: %{actor: current_user, tenant: "acme", order_id: "123"}
  )
```

For compiled agents, per-turn `context:` is parsed through the agent `schema`
when one is configured; schema defaults become the agent's default context.
Imported agents keep a plain default `context` map and merge per-turn values
over it.

`context` is:

- runtime-only application data for this turn
- available to hooks, dynamic `system_prompt`, tools, and `ash_resource`
- distinct from internal agent state
- distinct from model-visible conversation context

Moto does not automatically inject `context` into prompts or messages. If you
want the model to see part of it, project it explicitly through a hook, tool,
or dynamic system prompt.

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

## Subagents

Subagents use the manager pattern: the parent agent sees each specialist as a
tool-like capability and stays in control of the conversation.

```elixir
subagents do
  subagent MyApp.ResearchAgent,
    as: "research_agent",
    description: "Ask the research specialist",
    target: :ephemeral,
    timeout: 30_000,
    forward_context: :public,
    result: :text
end
```

`target` can be `:ephemeral`, `{:peer, "running-agent-id"}`, or
`{:peer, {:context, :agent_id_key}}`. Persistent peers must already be running;
Moto does not auto-start them.

`forward_context` controls what public runtime context reaches the child:
`:public`, `:none`, `{:only, keys}`, or `{:except, keys}`. Moto internal keys
and `memory` are never forwarded.

`result: :text` returns `%{result: child_text}` to the parent model.
`result: :structured` returns `%{result: child_text, subagent: metadata}` with
bounded execution metadata. Child output is still text in v1.

The runnable orchestrator example shows:

- a compiled manager agent
- a compiled `research_agent` subagent using `timeout`, `forward_context`, and `result: :structured`
- an imported JSON `writer_specialist` subagent using `Moto.ImportedAgent.Subagent`

The imported manager reference spec at
`examples/orchestrator/imported/sample_manager_agent.json` shows the equivalent
JSON `subagents` shape.

## Demo CLI

Interactive:

```bash
mix moto chat
```

This starts the demo agent in a simple REPL immediately. Type `exit` to quit.
Use `--log-level debug` for a compact per-turn trace or `--log-level trace` for
full config and event detail.

One-shot:

```bash
mix moto chat -- "Use the add_numbers tool to add 17 and 25. Reply with only the sum."
mix moto chat --log-level debug -- "Remember that my favorite color is blue."
mix moto chat --log-level trace -- "Use the add_numbers tool to add 17 and 25. Reply with only the sum."
```

Imported JSON agent:

```bash
mix moto imported
mix moto imported -- "Use the add_numbers tool to add 17 and 25. Reply with only the sum."
mix moto imported --log-level trace -- "Use the add_numbers tool to add 17 and 25. Reply with only the sum."
```

The sample imported agent spec lives at `examples/chat/imported/sample_math_agent.json`.

Orchestrator demo:

```bash
mix moto orchestrator
mix moto orchestrator -- "Use the research_agent specialist to explain vector databases."
mix moto orchestrator --log-level trace -- "Use the writer_specialist specialist to rewrite this copy: our setup is easier now."
```

Use `--log-level trace` to see subagent config and delegation metadata.

Kitchen sink showcase:

```bash
mix moto kitchen_sink --log-level trace --dry-run
mix moto kitchen_sink -- "Use the research_agent specialist to explain embeddings."
```

The kitchen sink demo intentionally combines schema, dynamic prompts, tools,
Ash resource expansion, skills, MCP tool sync, plugins, hooks, guardrails,
memory, compiled subagents, and imported JSON subagents in one place. It is a
showcase, not the recommended starting point.

The example source modules live under `examples/`. `mix moto` is the canonical
entrypoint for running them.

## Inspection

Moto exposes a small inspection surface for definitions and runs:

```elixir
{:ok, definition} = Moto.inspect_agent(MyApp.ChatAgent)
{:ok, imported} = Moto.inspect_agent(imported_agent)
{:ok, running} = Moto.inspect_agent(pid)

{:ok, latest_request} = Moto.inspect_request(pid)
{:ok, specific_request} = Moto.inspect_request(pid, "req-123")
```

Compiled Moto agents publish `__moto__/0` internally, and generated runtime
modules publish `__moto_definition__/0`, but `Moto.inspect_agent/1` is the
public entrypoint.

## Imported Agents

Moto also supports a constrained runtime import path for the same minimal agent
shape.

JSON:

```elixir
json = ~S"""
{
  "name": "json_agent",
  "model": "fast",
  "system_prompt": "You are a concise assistant.",
  "context": {
    "tenant": "json-demo",
    "channel": "imported"
  },
  "skills": ["math-discipline"],
  "skill_paths": ["../skills"],
  "plugins": ["math_plugin"],
  "hooks": {
    "before_turn": ["reply_with_final_answer"]
  },
  "guardrails": {
    "input": ["safe_prompt"],
    "output": ["safe_reply"],
    "tool": ["approve_refund_tool"]
  }
}
"""

{:ok, agent} =
  Moto.import_agent(
    json,
    available_plugins: [MyApp.Plugins.Math],
    available_hooks: [MyApp.Hooks.ReplyWithFinalAnswer],
    available_guardrails: [
      MyApp.Guardrails.SafePrompt,
      MyApp.Guardrails.SafeReply,
      MyApp.Guardrails.ApproveRefundTool
    ]
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
context:
  tenant: "yaml-demo"
  channel: "imported"
plugins:
  - "math_plugin"
skills:
  - "math-discipline"
skill_paths:
  - "../skills"
hooks:
  before_turn:
    - "reply_with_final_answer"
guardrails:
  input:
    - "safe_prompt"
  output:
    - "safe_reply"
  tool:
    - "approve_refund_tool"
"""

{:ok, agent} = Moto.import_agent(yaml,
  format: :yaml,
  available_plugins: [MyApp.Plugins.Math],
  available_hooks: [MyApp.Hooks.ReplyWithFinalAnswer],
  available_guardrails: [
    MyApp.Guardrails.SafePrompt,
    MyApp.Guardrails.SafeReply,
    MyApp.Guardrails.ApproveRefundTool
  ]
)
```

The imported-agent path is intentionally narrower than the Elixir DSL:

- only `name`
- only `model`
- only `system_prompt`
- only default `context` as a plain map
- only published tool names through `tools`
- only published skill names through `skills`
- only skill load paths through `skill_paths`
- only MCP sync settings through `mcp_tools`
- only published plugin names through `plugins`
- only published hook names through `hooks`
- only published guardrail names through `guardrails`
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
- `skills` supports:
  - string names like `["math-discipline"]`
  - explicit resolution through `available_skills: [MyApp.Skills.MathDiscipline]`
  - runtime path loading through `skill_paths`
- `mcp_tools` supports:
  - objects like `%{"endpoint" => "github", "prefix" => "github_"}`
- `hooks` supports:
  - a stage-keyed map like `%{"before_turn" => ["reply_with_final_answer"]}`
  - multiple names per stage
  - explicit resolution through `available_hooks: [MyApp.Hooks.ReplyWithFinalAnswer]`
- `guardrails` supports:
  - a stage-keyed map like `%{"input" => ["safe_prompt"]}`
  - multiple names per stage
  - explicit resolution through `available_guardrails: [MyApp.Guardrails.SafePrompt]`

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

- The shared runtime lives in `Moto.Runtime` and is started by the application supervisor.
- `Moto.Agent` uses a very small Spark DSL and generates a nested runtime module.
- `Moto.Tool` is a thin wrapper over `Jido.Action`, but it restricts tool schemas to Zoi.
- `Moto.Plugin` is a thin wrapper over `Jido.Plugin` and currently focuses on contributing tools.
- `Moto.Hook` is a thin wrapper for turn-scoped hook modules and interrupt-aware callbacks.
- `Moto.Guardrail` is a thin wrapper for input/output/tool validation modules.
- `Moto.model/1` resolves Moto-owned aliases first, then delegates to Jido.AI.
- Dynamic imports use a hidden runtime module generated from a validated Zoi spec.
- Imported tools, plugins, hooks, and guardrails are constrained to explicit allowlist registries.
- Imported skills can resolve through `available_skills`, runtime `skill_paths`, or both.
- The nested runtime module still uses `Jido.AI.Agent` underneath.
