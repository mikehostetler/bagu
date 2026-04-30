# Getting Started

This guide builds the smallest useful Jidoka agent, starts it, chats with it, and
handles errors correctly.

## Install

Jidoka beta releases are distributed through Hex:

```elixir
def deps do
  [
    {:jidoka, "~> 1.0.0-beta.1"}
  ]
end
```

During beta development, you can also pin a specific Git commit:

```elixir
def deps do
  [
    # Replace COMMIT_SHA with the Jidoka commit you are testing.
    {:jidoka,
     git: "https://github.com/agentjido/jidoka.git",
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
  end

  defaults do
    model :fast
    instructions "You are a concise assistant. Answer directly."
  end
end
```

The DSL has five sections:

- `agent do`: stable identity and optional context schema
- `defaults do`: model and required instructions
- `capabilities do`: tools and orchestration features, when needed
- `lifecycle do`: memory, hooks, and guardrails, when needed
- `schedules do`: recurring agent turns, when needed

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

## Next Steps

- [Agents](agents.html): the full DSL sections and generated functions.
- [Running Agents](running-agents.html): choose where the agent lives in your OTP app.
- [Schedules](schedules.html): run agents and workflows from Jidoka's schedule manager.
- [AgentView](agent-view.html): adapt an agent to a UI, API, job, or test boundary.
- [Structured Output](structured-output.html): return typed maps validated by Zoi instead of free text.
- [Tools](tools.html): give the agent deterministic capabilities to call mid-turn.
- [Chat Turn](chat-turn.html): per-turn options, return shapes, and how to opt out of structured parsing with `output: :raw`.
