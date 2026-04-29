# Errors

Jidoka public runtime APIs return structured success, interrupt, handoff, or
error shapes. Pattern-match on those shapes at application boundaries, format
them for users with `Jidoka.format_error/1`, and reach into
`reason.details.cause` only when an application owns that specific failure mode.

## Minimal example

```elixir
case Jidoka.chat(pid, "Hello") do
  {:ok, reply} ->
    reply

  {:error, reason} ->
    Logger.warning(Jidoka.format_error(reason))
end
```

## Public return shapes

`Jidoka.chat/3` and a generated agent's `chat/3` return one of:

```elixir
{:ok, value}
{:interrupt, %Jidoka.Interrupt{}}
{:handoff, %Jidoka.Handoff{}}
{:error, %Jidoka.Error.ValidationError{}}
{:error, %Jidoka.Error.ConfigError{}}
{:error, %Jidoka.Error.ExecutionError{}}
```

`Jidoka.Workflow.run/3` returns:

```elixir
{:ok, output}
{:error, %Jidoka.Error.ValidationError{}}
{:error, %Jidoka.Error.ConfigError{}}
{:error, %Jidoka.Error.ExecutionError{}}
```

The lifecycle that produces these shapes is documented in
[chat-turn.md](chat-turn.md).

## Error classes

Jidoka normalizes failures into three structs. Each struct carries a human
`message` and a `details` map with a `:cause` key holding the underlying term.

### ValidationError

The caller supplied invalid runtime input.

```elixir
{:error, reason} = Jidoka.chat(pid, "Hello", context: "acct_123")
Jidoka.format_error(reason)
#=> "Invalid context: pass `context:` as a map or keyword list."
```

### ConfigError

The runtime target or module configuration is invalid.

```elixir
{:error, reason} = Jidoka.inspect_workflow(NotAWorkflow)
Jidoka.format_error(reason)
#=> "Module is not a Jidoka workflow."
```

### ExecutionError

Configured work failed at runtime (chat, workflow, hook, guardrail, memory,
subagent, handoff, MCP).

```elixir
{:error, reason} = Jidoka.Workflow.run(MyApp.Workflows.FailingWorkflow, %{})
Jidoka.format_error(reason)
#=> "Workflow execution failed."
```

## Formatting errors

`Jidoka.format_error/1` returns a user-safe string for any Jidoka error
struct. It also falls back to `inspect/1` for unknown terms, so it is safe to
call on anything reaching an application boundary.

```elixir
Jidoka.format_error(reason)
```

Use this in logs, CLI output, LiveView flash messages, and other
user-facing surfaces.

## Low-level cause

Every Jidoka error carries `reason.details.cause` with the underlying term
that produced the failure. Use it for tests, observability, and code paths
that own a specific failure mode. Do not pattern-match on it from generic
callers: the cause shape is per-operation and may change as Jidoka evolves.

```elixir
case Jidoka.chat(pid, prompt) do
  {:ok, reply} ->
    reply

  {:error, %Jidoka.Error.ExecutionError{details: %{cause: :timeout}}} ->
    {:retry, prompt}

  {:error, reason} ->
    {:error, Jidoka.format_error(reason)}
end
```

For deeper visibility into a specific request (tools, subagents, memory,
usage), see [inspection.md](inspection.md). For time-series run data, see
[tracing.md](tracing.md).

## CLI error display

Demo CLIs and Mix tasks print errors through `Jidoka.format_error/1`. Mirror
that pattern in your own commands:

```elixir
case MyApp.SupportAgent.chat(pid, prompt) do
  {:ok, reply} -> IO.puts(reply)
  {:handoff, handoff} -> IO.inspect(handoff)
  {:interrupt, interrupt} -> IO.inspect(interrupt)
  {:error, reason} -> IO.puts("error> #{Jidoka.format_error(reason)}")
end
```

## See also

- [chat-turn.md](chat-turn.md): the lifecycle that produces these shapes.
- [inspection.md](inspection.md): inspect agents, requests, and workflows.
- [tracing.md](tracing.md): time-series run data and telemetry.
- [mix-tasks.md](mix-tasks.md): CLI patterns that use `format_error/1`.

## Imported agents

Imported agents reach the same Jidoka runtime, so they return the same
`Jidoka.Error.ValidationError`, `Jidoka.Error.ConfigError`, and
`Jidoka.Error.ExecutionError` structs through the same facade.
`Jidoka.format_error/1` and `details.cause` work identically. See
[imported-agents.md](imported-agents.md).
