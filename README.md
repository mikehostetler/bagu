# Bagu

Minimal harness layer over Jido and Jido.AI for defining and starting chat agents.

## Status

`bagu` is currently a pre-beta package.

The beta surface is being stabilized around agents, workflows, runtime errors,
imports, and examples. APIs outside the documented Bagu facade may still change
before a public Hex release.

This beta implementation keeps the Spark DSL deliberately structured: immutable
agent identity, runtime defaults, capabilities, and lifecycle policy are
declared in separate sections.

## Installation

Bagu is not published to Hex yet. For local beta-candidate work, use the repository
directly:

```elixir
def deps do
  [
    {:bagu, git: "https://github.com/mikehostetler/bagu.git", branch: "main"}
  ]
end
```

When Bagu is published, this section will be replaced with the Hex dependency
and any Igniter installer instructions.

## Overview

Bagu currently gives you a narrow, developer-friendly way to build chat-style
LLM agents on top of Jido and Jido.AI.

Today, Bagu can:

- define agents with a small Spark DSL via `use Bagu.Agent`
- configure agent `id`, runtime context `schema`, runtime `defaults`,
  `capabilities`, and `lifecycle`
- resolve models through Bagu-owned aliases like `:fast`, direct model strings,
  inline maps, and `%LLMDB.Model{}`
- support static or dynamic instructions through strings, module callbacks,
  and MFA tuples
- define tools with `use Bagu.Tool` as a thin, Zoi-only wrapper over `Jido.Action`
- compose prompt-level agent skills from Jido.AI skills, including runtime
  `SKILL.md` files
- sync remote MCP tool catalogs into an agent with `mcp_tools`
- attach tools directly or expose all generated `AshJido` actions for an Ash
  resource with `ash_resource`
- define plugins with `use Bagu.Plugin` and let them contribute tools into the
  agent's visible tool registry
- define reusable `Bagu.Hook` modules and attach them as default turn hooks or
  per-request overrides
- define reusable `Bagu.Guardrail` modules and attach them as default
  input/output/tool validation stages or per-request overrides
- enable conversation-first memory with bounded retrieval and opt-in
  auto-capture on top of `jido_memory`
- compose structured character/persona prompts through `jido_character`
- start many runtime instances from the same agent module under the shared
  `Bagu.Runtime`
- define explicit deterministic workflows with `use Bagu.Workflow`, backed by
  `jido_runic`, for multi-step tool/function/agent pipelines
- expose deterministic workflows to agents as tool-like capabilities when a
  chat turn needs a fixed business process
- import constrained agents from JSON or YAML at runtime with explicit
  allowlists for tools, plugins, hooks, and guardrails, including default
  imported context and memory settings
- run local demo scripts that exercise full LLM + tool-call loops

Bagu is intentionally opinionated. It keeps the public surface focused on
common agent authoring and hides most low-level Jido runtime machinery by
default.

## Setup

Set your Anthropic API key:

```bash
export ANTHROPIC_API_KEY=sk-ant-...
```

Or copy `.env.example` to `.env` and fill in the key.

`bagu` uses `dotenvy` in `config/runtime.exs` to load `.env` automatically at
runtime. Shell environment variables still win over `.env` values.

`bagu` owns its model aliases under `config :bagu, :model_aliases`.
By default, `:fast` maps to `anthropic:claude-haiku-4-5`.

For package development:

```bash
mix setup
mix test
mix quality
```

`mix quality` follows the Jido package quality baseline: formatting, compiler
warnings, Credo, Dialyzer, and documentation coverage.

Coverage is enforced with ExCoveralls at the current pre-beta baseline of 70%.
The Jido package target is 90%; Bagu should raise this before any stable
release.

The generated runtime currently uses:

- the DSL-configured `defaults.model` value, defaulting to `:fast`
- the DSL-configured context `schema`
- the DSL-configured `lifecycle.memory`
- the DSL-configured `capabilities`
- the DSL-configured `lifecycle` hooks and guardrails

Model configuration lives in:

- `config/config.exs` maps `:fast` under `config :bagu, :model_aliases`
- `config/runtime.exs` loads `.env` and configures `:req_llm`

## Define An Agent

```elixir
defmodule MyApp.ChatAgent do
  use Bagu.Agent

  agent do
    id :chat_agent

    schema Zoi.object(%{
      tenant: Zoi.string() |> Zoi.default("demo"),
      channel: Zoi.string() |> Zoi.default("web")
    })
  end

  defaults do
    model :fast
    instructions "You are a concise assistant."
  end
end
```

The DSL currently supports:

- `agent do`: required `id`, optional `description`, optional Zoi `schema`
- `defaults do`: required `instructions`, optional `model`, optional `character`
- `capabilities do`: `tool`, `ash_resource`, `mcp_tools`, `skill`, `load_path`, `plugin`, `subagent`, and `workflow`
- `lifecycle do`: `memory`, hooks, and guardrails

`model` accepts the same shapes Jido.AI and ReqLLM support:

- alias atoms like `:fast`
- direct model strings like `"anthropic:claude-haiku-4-5"`
- inline maps like `%{provider: :anthropic, id: "claude-haiku-4-5"}`
- `%LLMDB.Model{}` structs

Example with all three:

```elixir
defmodule MyApp.SupportAgent do
  use Bagu.Agent

  agent do
    id :support_agent
  end

  defaults do
    model "anthropic:claude-haiku-4-5"
    instructions "You help customers with support questions."
  end
end
```

`instructions` supports three forms:

- a static string
- a module implementing `resolve_system_prompt/1`
- an MFA tuple like `{MyApp.SupportPrompt, :build, ["prefix"]}`

Module-based dynamic prompt:

```elixir
defmodule MyApp.SupportPrompt do
  @behaviour Bagu.Agent.SystemPrompt

  @impl true
  def resolve_system_prompt(%{context: context}) do
    tenant = Map.get(context, :tenant, "unknown")
    "You help support users for tenant #{tenant}."
  end
end

defmodule MyApp.SupportAgent do
  use Bagu.Agent

  agent do
    id :support_agent
  end

  defaults do
    model :fast
    instructions MyApp.SupportPrompt
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
  use Bagu.Agent

  agent do
    id :support_agent
  end

  defaults do
    model :fast
    instructions {MyApp.SupportPrompts, :build, ["Support tenant"]}
  end
end
```

Dynamic instructions resolve once per turn through Jido.AI's request
transformer hook, using the current runtime context.

## Characters

Characters are structured persona inputs rendered into the effective system
prompt before `defaults.instructions`. They shape voice, identity, knowledge,
and behavioral style; they do not replace tools, memory, workflows, or
handoffs.

Compile-time character:

```elixir
defmodule MyApp.SupportAgent do
  use Bagu.Agent

  agent do
    id :support_agent
  end

  defaults do
    model :fast

    character %{
      name: "Support Advisor",
      identity: %{role: "Billing support specialist"},
      voice: %{tone: :professional, style: "Clear and direct"},
      instructions: ["Stay within published policy."]
    }

    instructions "Answer with the relevant policy first."
  end
end
```

Runtime character override:

```elixir
Bagu.chat(pid, "Can I get a refund?",
  character: %{
    name: "Escalation Advisor",
    voice: %{tone: :warm},
    instructions: ["Be brief and empathetic."]
  }
)
```

Character sources can be:

- an inline map parsed by `Jido.Character.new/1`
- a module generated with `use Jido.Character`

The prompt order is character first, then `defaults.instructions`, then Bagu
skill and memory sections. Per-request `character:` overrides the compile-time
character for that turn.

## Define A Workflow

Use a workflow when the application owns a deterministic multi-step process and
the data dependencies should be explicit. Agent turns are still the right default
for open-ended chat/tool reasoning; subagents are capabilities inside an agent
turn; workflows coordinate app-owned steps.

```elixir
defmodule MyApp.Workflows.MathPipeline do
  use Bagu.Workflow

  workflow do
    id :math_pipeline
    description "Adds one to a value and doubles the result."
    input Zoi.object(%{value: Zoi.integer()})
  end

  steps do
    tool :add, MyApp.Tools.AddAmount,
      input: %{
        value: input(:value),
        amount: value(1)
      }

    function :normalize, {MyApp.WorkflowFns, :normalize, 2},
      input: %{value: from(:add, :value)}

    agent :review, {:imported, :reviewer},
      prompt: from(:normalize, :prompt),
      context: %{value: input(:value)}
  end

  output from(:review)
end
```

Run a workflow through either API:

```elixir
{:ok, output} = MyApp.Workflows.MathPipeline.run(%{value: 5})

{:ok, debug} =
  Bagu.Workflow.run(MyApp.Workflows.MathPipeline, %{value: 5},
    agents: %{reviewer: reviewer_agent},
    return: :debug
  )
```

Workflow refs are explicit:

- `input(:key)` reads the parsed workflow input.
- `from(:step)` and `from(:step, :field)` read prior step output.
- `context(:key)` reads runtime side-band context from `opts[:context]`.
- `value(term)` marks a static value.

`Bagu.inspect_workflow/1` returns a stable definition map with workflow id,
steps, dependencies, and output selection. Debug workflow runs can include
internal graph data, but raw Runic graph structures are not part of the stable
Bagu authoring surface.

## Default Context

Agents can define a runtime context schema directly in the `agent` block:

```elixir
defmodule MyApp.ChatAgent do
  use Bagu.Agent

  agent do
    id :chat_agent

    schema Zoi.object(%{
      tenant: Zoi.string() |> Zoi.default("demo"),
      channel: Zoi.string() |> Zoi.default("web"),
      actor: Zoi.any() |> Zoi.optional(),
      order_id: Zoi.string() |> Zoi.optional()
    })
  end

  defaults do
    model :fast
    instructions "You are a concise assistant."
  end
end
```

Schema defaults are available through `MyApp.ChatAgent.context/0`. Per-turn
`context:` passed to `chat/3` is parsed through `MyApp.ChatAgent.context_schema/0`
before hooks, tools, guardrails, memory, and subagents see it.

Required context fields fail before a model call starts, while defaulted fields
remain available as agent defaults:

```elixir
defmodule MyApp.BillingAgent do
  use Bagu.Agent

  agent do
    id :billing_agent

    schema Zoi.object(%{
      account_id: Zoi.string(),
      tenant: Zoi.string() |> Zoi.default("demo")
    })
  end

  defaults do
    model :fast
    instructions "You help with billing questions."
  end
end

MyApp.BillingAgent.context()
#=> %{tenant: "demo"}

{:error, %Bagu.Error.ValidationError{} = reason} =
  MyApp.BillingAgent.chat(pid, "Show my invoice.")

Bagu.format_error(reason)
#=> "Invalid context:\n- account_id: is required"

{:ok, reply} =
  MyApp.BillingAgent.chat(pid, "Show my invoice.",
    context: %{account_id: "acct_123"}
  )
```

## Runtime Errors

Bagu runtime APIs return structured Bagu/Splode errors:

```elixir
case Bagu.chat("missing-agent", "Hello") do
  {:ok, reply} ->
    reply

  {:interrupt, interrupt} ->
    interrupt

  {:error, reason} ->
    Bagu.format_error(reason)
end
```

Common runtime failures use one of:

- `%Bagu.Error.ValidationError{}` for invalid inputs or missing runtime data
- `%Bagu.Error.ConfigError{}` for invalid runtime configuration
- `%Bagu.Error.ExecutionError{}` for failed tools, workflows, memory, MCP,
  hooks, guardrails, or subagents

Original low-level causes are preserved in `reason.details.cause` for debugging.

## Memory

Bagu memory is conversation-first and opt-in. It is implemented on top of
`jido_memory`, but Bagu keeps the public surface narrow:

```elixir
defmodule MyApp.ChatAgent do
  use Bagu.Agent

  agent do
    id :chat_agent
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

V1 memory supports only:

- `mode :conversation`
- `namespace :per_agent`
- `namespace :shared` with `shared_namespace "..."`
- `namespace {:context, key}`
- `capture :conversation` or `:off`
- `retrieve limit: n`
- `inject :instructions` or `:context`

`inject :instructions` appends a bounded `Relevant memory:` section to the
effective instructions for the turn.

`inject :context` exposes retrieved records at `context.memory` for hooks,
tools, and plugins without automatically projecting memory into the prompt.

Memory is opt-in:

- no `lifecycle do memory do ... end end` means no memory lifecycle at all
- `capture :off` disables writes but still allows retrieval from an existing
  namespace
- imported JSON/YAML agents support the same constrained memory subset

## Define A Tool

```elixir
defmodule MyApp.Tools.AddNumbers do
  use Bagu.Tool,
    description: "Adds two integers together.",
    schema: Zoi.object(%{a: Zoi.integer(), b: Zoi.integer()})

  @impl true
  def run(%{a: a, b: b}, _context) do
    {:ok, %{sum: a + b}}
  end
end
```

`Bagu.Tool` is a thin wrapper over `Jido.Action`. It defaults the published
tool name from the module name and keeps the runtime contract as a plain Jido
action module.

Bagu tools are Zoi-only for `schema` and `output_schema`. NimbleOptions and raw
JSON Schema maps are intentionally not supported through the Bagu API.

## Attach Tools To An Agent

```elixir
defmodule MyApp.MathAgent do
  use Bagu.Agent

  agent do
    id :math_agent
  end

  defaults do
    model :fast
    instructions "You can use math tools."
  end

  capabilities do
    tool MyApp.Tools.AddNumbers
  end
end
```

You can also expose all generated `AshJido` actions for a resource:

```elixir
defmodule MyApp.UserAgent do
  use Bagu.Agent

  agent do
    id :user_agent
  end

  defaults do
    model :fast
    instructions "You can use account tools."
  end

  capabilities do
    ash_resource MyApp.Accounts.User
  end
end
```

For `ash_resource` tools, Bagu will:

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

Bagu skills are built on top of `Jido.AI.Skill`.

You can attach:

- module-based skills defined with `use Jido.AI.Skill`
- runtime-loaded `SKILL.md` files by published skill name plus `load_path`

```elixir
defmodule MyApp.MathAgent do
  use Bagu.Agent

  agent do
    id :math_agent
  end

  defaults do
    model :fast
    instructions "You are a concise assistant."
  end

  capabilities do
    skill "math-discipline"
    load_path "../skills"
  end
end
```

Bagu uses skills in two ways:

- renders skill prompt text into the effective system prompt
- narrows the visible tool set when the skill declares `allowed-tools`

Module-based skills can also contribute action-backed tools through their
`actions:` list.

## Sync MCP Tools

Bagu treats MCP servers as a first-class tool source. Tools can be synced from
configured `jido_mcp` endpoints, runtime-registered endpoints, or inline
compiled-agent endpoint definitions:

```elixir
defmodule MyApp.GitHubAgent do
  use Bagu.Agent

  agent do
    id :github_agent
  end

  defaults do
    model :fast
    instructions "You can use GitHub MCP tools."
  end

  capabilities do
    mcp_tools endpoint: :github, prefix: "github_"
  end
end
```

Runtime registration is useful when endpoint configuration belongs in
application code instead of static config:

```elixir
{:ok, _endpoint} =
  Bagu.MCP.register_endpoint(:workspace_fs,
    transport:
      {:stdio,
       [
         command: "npx",
         args: ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"]
       ]},
    client_info: %{name: "my_app", version: "1.0.0"}
  )
```

Compiled agents can also declare an inline endpoint. Bagu registers it
idempotently before the first turn and syncs the tools before the model runs:

```elixir
capabilities do
  mcp_tools endpoint: :workspace_fs,
            prefix: "fs_",
            transport:
              {:stdio,
               [
                 command: "npx",
                 args: ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"]
               ]},
            client_info: %{name: "my_app", version: "1.0.0"}
end
```

Bagu keeps MCP narrow in this first pass:

- MCP is treated as another tool source
- tools are synced before the model turn runs
- Bagu does not currently expose raw MCP resources or prompts
- imported JSON/YAML specs reference endpoint names only; executable transport
  configuration stays in code or application config

## Define A Plugin

```elixir
defmodule MyApp.Plugins.Math do
  use Bagu.Plugin,
    description: "Provides extra math tools.",
    tools: [MyApp.Tools.MultiplyNumbers]
end
```

`Bagu.Plugin` is a thin wrapper over `Jido.Plugin`. In this first pass, the
Bagu-facing plugin contract is intentionally small:

- publish a stable plugin name
- register action-backed tools
- let Bagu merge those tools into the agent's LLM-visible tool registry

## Attach Plugins To An Agent

```elixir
defmodule MyApp.MathAgent do
  use Bagu.Agent

  agent do
    id :math_agent
  end

  defaults do
    model :fast
    instructions "You can use math tools."
  end

  capabilities do
    plugin MyApp.Plugins.Math
  end
end
```

Plugin-provided tools are merged into `MyApp.MathAgent.tools/0` and exposed to
the underlying Jido.AI runtime just like tools registered directly in the
`capabilities do ... end` block.

## Define A Hook

```elixir
defmodule MyApp.Hooks.ReplyWithFinalAnswer do
  use Bagu.Hook, name: "reply_with_final_answer"

  @impl true
  def call(%Bagu.Hooks.BeforeTurn{} = input) do
    {:ok, %{message: "#{input.message}\n\nReply with only the final answer."}}
  end
end
```

`Bagu.Hook` is a thin wrapper for turn-scoped callouts. A hook publishes a
stable name and exposes a single `call/1` callback.

Bagu currently supports three hook stages:

- `before_turn`
- `after_turn`
- `on_interrupt`

DSL hooks accept Bagu hook modules or MFA tuples. Request-scoped `chat/3`
hooks also accept anonymous arity-1 functions.

## Attach Hooks To An Agent

```elixir
defmodule MyApp.ChatAgent do
  use Bagu.Agent

  agent do
    id :chat_agent
  end

  defaults do
    model :fast
    instructions "You are a concise assistant."
  end

  lifecycle do
    before_turn MyApp.Hooks.ReplyWithFinalAnswer
    before_turn {MyApp.Hooks.AuditTurn, :call, [:support]}
    after_turn MyApp.Hooks.NormalizeReply
    on_interrupt MyApp.Hooks.NotifyOps
  end
end
```

Multiple hooks are allowed per stage. Bagu stores them stage-by-stage and runs:

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
  use Bagu.Guardrail, name: "safe_prompt"

  @impl true
  def call(%Bagu.Guardrails.Input{message: message}) do
    if String.contains?(String.downcase(message), "secret") do
      {:error, :unsafe_prompt}
    else
      :ok
    end
  end
end
```

`Bagu.Guardrail` is a thin wrapper for validation-only turn boundaries. A
guardrail publishes a stable name and exposes a single `call/1` callback.

Bagu currently supports three guardrail stages:

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
  use Bagu.Agent

  agent do
    id :chat_agent
  end

  defaults do
    model :fast
    instructions "You are a concise assistant."
  end

  lifecycle do
    input_guardrail MyApp.Guardrails.SafePrompt
    output_guardrail {MyApp.Guardrails.SafeReply, :call, [:support]}
    tool_guardrail MyApp.Guardrails.ApproveRefundTool
  end
end
```

Multiple guardrails are allowed per stage. Bagu runs them in declaration order
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
runtime_before_turn = fn %Bagu.Hooks.BeforeTurn{} = input ->
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
If a hook interrupts the turn, Bagu returns:

```elixir
{:interrupt, %Bagu.Interrupt{}}
```

## Per-Turn Guardrail Overrides

You can also pass guardrails directly to `chat/3`:

```elixir
runtime_input_guardrail = fn %Bagu.Guardrails.Input{} = input ->
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
that turn. When a guardrail blocks, Bagu returns:

```elixir
{:error, %Bagu.Error.ExecutionError{} = reason}
Bagu.format_error(reason)
#=> "Guardrail safe_prompt blocked input."
```

When a guardrail interrupts, Bagu returns:

```elixir
{:interrupt, %Bagu.Interrupt{}}
```

## Runtime Context

Bagu uses `context:` as the public name for request-scoped runtime data.

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
- available to hooks, dynamic `instructions`, tools, and `ash_resource`
- distinct from internal agent state
- distinct from model-visible conversation context

Bagu does not automatically inject `context` into prompts or messages. If you
want the model to see part of it, project it explicitly through a hook, tool,
or dynamic instructions.

## Start And Chat

```elixir
{:ok, pid} = MyApp.ChatAgent.start_link(id: "chat-1")
{:ok, reply} = MyApp.ChatAgent.chat(pid, "Write a one-line haiku about Elixir.")
```

Or through the top-level Bagu runtime facade:

```elixir
{:ok, pid} = MyApp.ChatAgent.start_link(id: "chat-1")
{:ok, reply} = Bagu.chat(pid, "Write a one-line haiku about Elixir.")
```

Or use the shared runtime facade directly:

```elixir
{:ok, pid} = Bagu.start_agent(MyApp.ChatAgent.runtime_module(), id: "chat-2")
{:ok, reply} = MyApp.ChatAgent.chat(pid, "Say hello.")
```

## Subagents

Subagents use the manager pattern: the parent agent sees each specialist as a
tool-like capability and stays in control of the conversation.

```elixir
capabilities do
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
Bagu does not auto-start them.

`forward_context` controls what public runtime context reaches the child:
`:public`, `:none`, `{:only, keys}`, or `{:except, keys}`. Bagu internal keys
and `memory` are never forwarded.

`result: :text` returns `%{result: child_text}` to the parent model.
`result: :structured` returns `%{result: child_text, subagent: metadata}` with
bounded execution metadata. Child output is still text in v1.

The runnable orchestrator example shows:

- a compiled manager agent
- a compiled `research_agent` subagent using `timeout`, `forward_context`, and `result: :structured`
- an imported JSON `writer_specialist` subagent using `Bagu.ImportedAgent.Subagent`

The imported manager reference spec at
`examples/orchestrator/imported/sample_manager_agent.json` shows the equivalent
JSON `subagents` shape.

## Workflow Capabilities

Agents can expose deterministic workflows as tool-like capabilities. Use this
when the agent should decide that a request needs a known business process, but
the ordered work should still run through `Bagu.Workflow`.

```elixir
capabilities do
  workflow MyApp.Workflows.RefundReview,
    as: :review_refund,
    description: "Review refund eligibility for a known account and order.",
    timeout: 30_000,
    forward_context: {:only, [:tenant, :session]},
    result: :structured
end
```

The generated tool uses the workflow input schema as its tool schema. By
default it returns `%{output: workflow_output}`. With `result: :structured`, it
also returns bounded workflow metadata for debugging. Workflow failures return
structured Bagu errors and should be displayed with `Bagu.format_error/1`.

## Demo CLI

Interactive:

```bash
mix bagu chat
```

This starts the demo agent in a simple REPL immediately. Type `exit` to quit.
Use `--log-level debug` for a compact per-turn trace or `--log-level trace` for
full config and event detail.

One-shot:

```bash
mix bagu chat -- "Use the add_numbers tool to add 17 and 25. Reply with only the sum."
mix bagu chat --log-level debug -- "Remember that my favorite color is blue."
mix bagu chat --log-level trace -- "Use the add_numbers tool to add 17 and 25. Reply with only the sum."
```

Imported JSON agent:

```bash
mix bagu imported
mix bagu imported -- "Use the add_numbers tool to add 17 and 25. Reply with only the sum."
mix bagu imported --log-level trace -- "Use the add_numbers tool to add 17 and 25. Reply with only the sum."
```

The sample imported agent spec lives at `examples/chat/imported/sample_math_agent.json`.

Orchestrator demo:

```bash
mix bagu orchestrator
mix bagu orchestrator -- "Use the research_agent specialist to explain vector databases."
mix bagu orchestrator --log-level trace -- "Use the writer_specialist specialist to rewrite this copy: our setup is easier now."
```

Use `--log-level trace` to see subagent config and delegation metadata.

Support example:

```bash
mix bagu support --log-level trace --dry-run
mix bagu support -- "Customer acct_vip says order ord_damaged arrived broken and wants a refund because it was damaged on arrival."
mix bagu support -- "/refund acct_vip ord_damaged Damaged on arrival"
mix bagu support -- "/escalate acct_trial Customer is locked out and threatening to cancel"
```

This example keeps the current boundary explicit: the chat agent owns open-ended
intake and subagent delegation, while workflows own fixed support processes.
One workflow is tool-only, and one reuses the writer specialist as a bounded
workflow step.

Kitchen sink showcase:

```bash
mix bagu kitchen_sink --log-level trace --dry-run
mix bagu kitchen_sink -- "Use the research_agent specialist to explain embeddings."
```

The kitchen sink demo intentionally combines schema, dynamic prompts, tools,
Ash resource expansion, skills, MCP tool sync, plugins, hooks, guardrails,
memory, compiled subagents, and imported JSON subagents in one place. It is a
showcase, not the recommended starting point.

The example source modules live under `examples/`. `mix bagu` is the canonical
entrypoint for running them.

## Live Agent Evals

Bagu includes a tagged live eval suite for the support example. These tests use
real provider calls and are excluded from normal `mix test` runs.

```bash
ANTHROPIC_API_KEY=... mix test --include llm_eval test/evals/support_agent_eval_test.exs
```

The support evals use the local `jido_eval` checkout as the dataset/result
harness, then run custom Bagu metrics for specialist routing and LLM-judged
support quality. If the tag is included without a real key, the suite fails
clearly instead of skipping.

## Inspection

Bagu exposes a small inspection surface for definitions and runs:

```elixir
{:ok, definition} = Bagu.inspect_agent(MyApp.ChatAgent)
{:ok, imported} = Bagu.inspect_agent(imported_agent)
{:ok, running} = Bagu.inspect_agent(pid)

{:ok, latest_request} = Bagu.inspect_request(pid)
{:ok, specific_request} = Bagu.inspect_request(pid, "req-123")
```

Compiled Bagu agents publish `__bagu__/0` internally, and generated runtime
modules publish `__bagu_definition__/0`, but `Bagu.inspect_agent/1` is the
public entrypoint.

## Imported Agents

Bagu also supports a constrained runtime import path for the same minimal agent
shape.

JSON:

```elixir
json = ~S"""
{
  "agent": {
    "id": "json_agent",
    "context": {
      "tenant": "json-demo",
      "channel": "imported"
    }
  },
  "defaults": {
    "model": "fast",
    "instructions": "You are a concise assistant."
  },
  "capabilities": {
    "skills": ["math-discipline"],
    "skill_paths": ["../skills"],
    "plugins": ["math_plugin"]
  },
  "lifecycle": {
    "hooks": {
      "before_turn": ["reply_with_final_answer"]
    },
    "guardrails": {
      "input": ["safe_prompt"],
      "output": ["safe_reply"],
      "tool": ["approve_refund_tool"]
    }
  }
}
"""

{:ok, agent} =
  Bagu.import_agent(
    json,
    available_plugins: [MyApp.Plugins.Math],
    available_hooks: [MyApp.Hooks.ReplyWithFinalAnswer],
    available_guardrails: [
      MyApp.Guardrails.SafePrompt,
      MyApp.Guardrails.SafeReply,
      MyApp.Guardrails.ApproveRefundTool
    ]
  )

{:ok, pid} = Bagu.start_agent(agent, id: "json-agent")
{:ok, reply} = Bagu.chat(pid, "Say hello.")
```

YAML:

```elixir
yaml = """
agent:
  id: "yaml_agent"
  context:
    tenant: "yaml-demo"
    channel: "imported"
defaults:
  model:
    provider: "openai"
    id: "gpt-4.1"
  instructions: |-
    You are a concise assistant.
capabilities:
  plugins:
    - "math_plugin"
  skills:
    - "math-discipline"
  skill_paths:
    - "../skills"
lifecycle:
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

{:ok, agent} = Bagu.import_agent(yaml,
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

- `agent.id`
- `agent.context` as a plain default map
- `defaults.model`
- `defaults.instructions`
- `defaults.character` as an inline character map or string ref resolved
  through `available_characters`
- published tool, skill, MCP, plugin, subagent, and workflow declarations under `capabilities`
- memory, hook, and guardrail declarations under `lifecycle`
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
  - endpoints may come from app config or runtime `Bagu.MCP.register_endpoint/2`
- `workflows` supports:
  - string names like `["refund_review"]`
  - objects like `%{"workflow" => "refund_review", "as" => "review_refund"}`
  - explicit resolution through `available_workflows: [MyApp.Workflows.RefundReview]`
- `character` supports:
  - inline character maps under `defaults.character`
  - modules generated with `use Jido.Character`
  - string refs like `"support_advisor"`
  - explicit resolution through `available_characters: %{"support_advisor" => MyApp.Characters.SupportAdvisor}`
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
It also does not support dynamic `instructions` callbacks yet, because the
constrained JSON/YAML format intentionally avoids executable Elixir references.
Imported workflow capabilities are supported through `capabilities.workflows`,
but workflow names must resolve through an explicit `available_workflows`
registry. Imported character refs must resolve through an explicit
`available_characters` registry; inline `Jido.Character` maps are portable.

The top-level helpers are:

- `Bagu.import_agent/2`
- `Bagu.import_agent_file/2`
- `Bagu.encode_agent/2`
- `Bagu.chat/3`

## Notes

- The shared runtime lives in `Bagu.Runtime` and is started by the application supervisor.
- `Bagu.Agent` uses a very small Spark DSL and generates a nested runtime module.
- Workflow capabilities let agents call deterministic Bagu workflows; raw Runic
  authoring remains internal.
- Characters render structured persona data into the effective system prompt
  before `defaults.instructions`.
- `Bagu.Tool` is a thin wrapper over `Jido.Action`, but it restricts tool schemas to Zoi.
- `Bagu.Plugin` is a thin wrapper over `Jido.Plugin` and currently focuses on contributing tools.
- `Bagu.Hook` is a thin wrapper for turn-scoped hook modules and interrupt-aware callbacks.
- `Bagu.Guardrail` is a thin wrapper for input/output/tool validation modules.
- `Bagu.model/1` resolves Bagu-owned aliases first, then delegates to Jido.AI.
- Dynamic imports use a hidden runtime module generated from a validated Zoi spec.
- Imported tools, characters, plugins, hooks, and guardrails are constrained to explicit allowlist registries.
- Imported skills can resolve through `available_skills`, runtime `skill_paths`, or both.
- The nested runtime module still uses `Jido.AI.Agent` underneath.
- Internal beta development can use local `jido_runic` and `jido_eval` path
  dependencies. A public Hex beta should replace local paths with Hex releases,
  Git refs, or pinned tags.
