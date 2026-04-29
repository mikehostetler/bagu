# Mix Tasks

Jidoka ships a single Mix task: `mix jidoka`. It dispatches to a small set of
named demos and to anything under `examples/` so that authors can exercise an
agent end-to-end without writing wrapper code. The same task drives provider
calls, configuration inspection (`--dry-run`), and provider-free contract
checks (`--verify`).

Run `mix jidoka --help` (or `-h`, or no arguments) to print the list of
recognized names. Built-in demos and discovered examples appear in one
alphabetized list.

## Built-in demos

Built-in demos are the curated entry points wired up in `Jidoka.Demo`:

| Command | What it shows |
| ------- | ------------- |
| `mix jidoka chat` | Single compiled chat agent with a tool, hooks, guardrails, plugins, and memory. |
| `mix jidoka imported` | Constrained JSON import path with explicit runtime registries. See [imported-agents.md](imported-agents.md). |
| `mix jidoka workflow` | Smallest deterministic workflow: add one, then double. |
| `mix jidoka orchestrator` | Manager agent that delegates to subagents. |
| `mix jidoka structured_output` | Typed output validation, including an invalid-output path. |
| `mix jidoka trace` | Provider-free smoke test for the structured trace collector. |
| `mix jidoka kitchen_sink` | Showcase combining schema, tools, Ash, skills, MCP, plugins, hooks, guardrails, memory, and subagents. |

Every built-in demo accepts the standard flags below. `--dry-run` prints the
compiled agent inventory and exits without contacting a provider.

## Example runner

`mix jidoka <name>` also runs anything in `examples/<name>/` that defines a
`demo.ex` module. Example names are discovered at task time, so adding a new
folder under `examples/` makes it runnable without touching the dispatcher.
See [examples.md](examples.md) for the canonical catalog.

Each canonical example supports `--verify`, which exercises the agent's tools
and structured output contract in process. Verification does not call a
provider, so it is safe to run in CI and on machines without an API key.

## Flags reference

The dispatcher and every demo accept the same flag set:

- `--dry-run`: print the compiled agent inventory and exit. No agent process
  is started and no provider is called.
- `--verify`: run the example's contract checks (tool round-trips, structured
  output validation). Provider-free.
- `--log-level info|debug|trace` (alias `-l`): controls runtime debug output.
  `info` is the default. `debug` enables agent debug logging. `trace` adds the
  full configuration dump and per-event trace lines.
- `--help`: print per-command usage.
- `--`: everything after the bare `--` is collected as the prompt. Prompts
  with spaces should be quoted by the shell.

A demo invoked without a prompt enters its interactive REPL when one is
defined; otherwise it runs a single canonical prompt.

## Concrete invocations

```bash
# Inspect the compiled chat agent without a provider call.
mix jidoka chat --dry-run

# One-shot prompt against a configured provider.
mix jidoka chat -- "Use one sentence to explain Jidoka."

# Provider-free contract check for a canonical example.
mix jidoka lead_qualification --verify

# Verbose configuration dump and event tracing for an orchestrator run.
mix jidoka orchestrator --log-level trace -- \
  "Use the research_agent specialist to explain vector databases."
```

Live runs require a provider key (for example, `ANTHROPIC_API_KEY`). See
[getting-started.md](getting-started.md) for the configuration walkthrough.

## Errors

Demos format failures with `Jidoka.format_error/1` and print them with an
`error>` prefix:

```
error> validation: tools[0].name is required
```

The `error>` line is human-facing; the underlying value is one of the
structured error structs documented in [errors.md](errors.md). Demos do not
swallow errors: the prefix is the only visual marker and the process exits
non-zero on Mix-level failures.

## Writing your own Mix task

Application Mix tasks should pattern-match on the public return shapes from
`Jidoka.chat/3` and friends, then format errors with `Jidoka.format_error/1`.
A minimal task looks like this:

```elixir
defmodule Mix.Tasks.MyApp.Chat do
  use Mix.Task

  @shortdoc "Run MyApp.SupportAgent against a single prompt"

  @impl true
  def run(argv) do
    Mix.Task.run("app.start")
    prompt = Enum.join(argv, " ")
    {:ok, pid} = MyApp.SupportAgent.start_link(id: "support-cli")

    case Jidoka.chat(pid, prompt) do
      {:ok, value} ->
        IO.puts(value)

      {:interrupt, interrupt} ->
        IO.puts("interrupt> #{interrupt.reason}")

      {:handoff, handoff} ->
        IO.puts("handoff> #{handoff.target}")

      {:error, reason} ->
        IO.puts("error> #{Jidoka.format_error(reason)}")
        exit({:shutdown, 1})
    end
  end
end
```

Tasks that wrap Jidoka should stick to the public facade (`Jidoka.chat/3`,
`Jidoka.start_agent/2`, `Jidoka.format_error/1`, the imported-agent helpers)
and let the four-shape return contract drive control flow.

## See also

- [getting-started.md](getting-started.md)
- [examples.md](examples.md)
- [errors.md](errors.md)
- [livebooks.md](livebooks.md)
- [imported-agents.md](imported-agents.md)

## Imported agents

Imported JSON and YAML specs are not a side path. `mix jidoka imported` is the
canonical entry point for runtime-imported agents, and the same `--dry-run`,
`--verify`, `--log-level`, and prompt conventions apply. See
[imported-agents.md](imported-agents.md) for the spec format and registry
wiring.
