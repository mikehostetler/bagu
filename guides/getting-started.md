# Getting Started

This guide builds the smallest useful Jidoka agent, starts it, chats with it, and
handles errors correctly.

## Install

Jidoka is pre-beta and is not published to Hex yet. Use the Git repository while
the beta surface is stabilizing:

```elixir
def deps do
  [
    # Replace COMMIT_SHA with the Jidoka commit you are testing.
    {:jidoka,
     git: "https://github.com/mikehostetler/jidoka.git",
     ref: "COMMIT_SHA"}
  ]
end
```

Then fetch dependencies:

```bash
mix deps.get
```

## Configure A Provider

The examples use Anthropic through ReqLLM/Jido.AI. Set an API key in the shell:

```bash
export ANTHROPIC_API_KEY=sk-ant-...
```

During local development, Jidoka also loads `.env` through `dotenvy` at runtime.
Shell environment variables still win over `.env` values.

Jidoka owns model aliases under `config :jidoka, :model_aliases`. In this repo,
`:fast` maps to `"anthropic:claude-haiku-4-5"`.

## Define An Agent

Create a module with `use Jidoka.Agent`:

```elixir
defmodule MyApp.AssistantAgent do
  use Jidoka.Agent

  agent do
    id :assistant_agent
    description "A small general-purpose assistant."
  end

  defaults do
    model :fast
    instructions "You are a concise assistant. Answer directly."
  end
end
```

The required shape is:

- `agent do`: stable identity and optional context schema
- `defaults do`: model and required instructions
- `capabilities do`: tools and orchestration features, when needed
- `lifecycle do`: memory, hooks, and guardrails, when needed

Only `agent.id` and `defaults.instructions` are required for a basic agent.

## Start And Chat

Start the generated runtime under Jidoka's shared supervisor:

```elixir
{:ok, pid} = MyApp.AssistantAgent.start_link(id: "assistant-1")
```

Send a message through the generated helper:

```elixir
{:ok, reply} = MyApp.AssistantAgent.chat(pid, "Write one sentence about Elixir.")
```

Or use the top-level facade:

```elixir
{:ok, reply} = Jidoka.chat(pid, "Write one sentence about Elixir.")
```

You can also start by runtime module:

```elixir
{:ok, pid} = Jidoka.start_agent(MyApp.AssistantAgent.runtime_module(), id: "assistant-2")
```

Use `Jidoka.stop_agent/1` when you own the runtime lifecycle manually:

```elixir
:ok = Jidoka.stop_agent(pid)
```

## Handle Results

Public chat calls return one of four shapes:

```elixir
case Jidoka.chat(pid, "Hello") do
  {:ok, reply} ->
    reply

  {:interrupt, interrupt} ->
    interrupt

  {:handoff, handoff} ->
    handoff

  {:error, reason} ->
    Jidoka.format_error(reason)
end
```

Use `Jidoka.format_error/1` at user-facing boundaries. Runtime errors are
structured Jidoka/Splode errors, but callers should not need to inspect internal
causes for normal display.

## Try The Built-In Demos

From the Jidoka package directory:

```bash
mix jidoka chat --dry-run
mix jidoka imported --dry-run
mix jidoka orchestrator --dry-run
mix jidoka workflow --dry-run
```

Remove `--dry-run` to start live examples. Live chat examples require provider
credentials.

```bash
mix jidoka chat -- "Use one sentence to explain what Jidoka is."
```

The full support demo lives in the Phoenix consumer app:

```bash
cd dev/jidoka_consumer
PORT=4002 mix phx.server
```

## Next Step

Read [Agents](agents.html) to understand the DSL sections and generated
functions before adding tools or orchestration.
