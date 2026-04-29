# Guardrails

Guardrails are validation and blocking checks that run at three boundaries of a
Jidoka chat turn. They give you a single, declarative place to refuse unsafe
input, vet model output, and gate tool calls before they execute. A guardrail
either allows the turn to continue or stops it with a normalized error.

Guardrails are declared inside `lifecycle do ... end` and exposed on the
generated module as [`guardrails/0`](inspection.md), grouped by stage.

## Minimal Example

```elixir
defmodule MyApp.Guardrails.NoSecrets do
  use Jidoka.Guardrail, name: "no_secrets"

  @impl true
  def call(%Jidoka.Guardrails.Input{message: message}) do
    if String.contains?(String.downcase(message), "secret") do
      {:error, :secret_request}
    else
      :ok
    end
  end
end

defmodule MyApp.SupportAgent do
  use Jidoka.Agent

  agent do
    id :support_agent
  end

  defaults do
    model :fast
    instructions "You help customers with support questions."
  end

  lifecycle do
    input_guardrail MyApp.Guardrails.NoSecrets
  end
end
```

A blocked turn surfaces through `Jidoka.chat/3` as
`{:error, %Jidoka.Error.ExecutionError{}}`.

## The Three Guardrail Kinds

Each kind receives a different input struct and runs at a different boundary.
All three share the same return contract:

- `:ok`: allow the turn to continue.
- `{:error, reason}`: block the turn; `reason` is normalized into a Jidoka error.
- `{:interrupt, %Jidoka.Interrupt{}}`: pause the turn and emit an interrupt
  notification (see [chat-turn.md](chat-turn.md)).

### `input_guardrail`

Runs after [hooks](hooks.md) rewrite the turn and before the LLM call. The
callback receives a `%Jidoka.Guardrails.Input{}` with fields including
`:message`, `:context`, `:allowed_tools`, `:llm_opts`, `:agent`, and
`:request_id`.

```elixir
@callback call(%Jidoka.Guardrails.Input{}) ::
            :ok | {:error, term()} | {:interrupt, Jidoka.Interrupt.t()}
```

Use this stage to refuse prompts, enforce tenancy, or validate context shape
before any provider call is made.

### `output_guardrail`

Runs after the model produces its final outcome and before Jidoka returns the
result. The callback receives a `%Jidoka.Guardrails.Output{}` whose extra
`:outcome` field is the request result, either `{:ok, result}` or
`{:error, error}`.

```elixir
@callback call(%Jidoka.Guardrails.Output{}) ::
            :ok | {:error, term()} | {:interrupt, Jidoka.Interrupt.t()}
```

Use this stage to redact responses, enforce schema invariants on
[structured output](structured-output.md), or block responses that leak data.

### `tool_guardrail`

Runs immediately before each model-selected tool call executes. The callback
receives a `%Jidoka.Guardrails.Tool{}` with `:tool_name`, `:tool_call_id`,
`:arguments`, `:context`, `:agent`, and `:request_id`.

```elixir
@callback call(%Jidoka.Guardrails.Tool{}) ::
            :ok | {:error, term()} | {:interrupt, Jidoka.Interrupt.t()}
```

Use this stage to enforce per-tool authorization or validate arguments against
runtime context. A blocked tool call propagates as a tool error to the model
and the turn surfaces as a guardrail-blocked execution error.

## Defining A Guardrail Module

Use the `Jidoka.Guardrail` behaviour and provide a published name:

```elixir
defmodule MyApp.Guardrails.TenantMatches do
  use Jidoka.Guardrail, name: "tenant_matches"

  @impl true
  def call(%Jidoka.Guardrails.Input{context: %{tenant: tenant}, message: message}) do
    if String.contains?(message, tenant), do: :ok, else: {:error, :tenant_mismatch}
  end
end
```

Notes:

- `name`: defaults to the underscored last module segment. Names must be unique
  within an [imported guardrail registry](imported-agents.md).
- Compile-time validation: `Jidoka.Guardrail` checks that `name/0` and `call/1`
  are exported and that `name/0` returns a non-empty string.
- Timeouts: each guardrail invocation is bounded at five seconds; exceeding the
  budget yields `{:error, :timeout}` and blocks the turn.

## Multiple Guardrails Per Stage

Each stage accepts any number of `input_guardrail`, `output_guardrail`, or
`tool_guardrail` declarations. Order is preserved.

```elixir
lifecycle do
  input_guardrail MyApp.Guardrails.NoSecrets
  input_guardrail MyApp.Guardrails.TenantMatches
  output_guardrail MyApp.Guardrails.RedactPii
  tool_guardrail MyApp.Guardrails.AllowedTools
end
```

Guardrails for a stage run sequentially. The first non-`:ok` result halts the
stage: later guardrails are skipped, and the offending guardrail's label is
recorded on the resulting error.

## Blocking Semantics

A blocked guardrail always normalizes to `Jidoka.Error.ExecutionError` with
`phase: :guardrail`. Details include the stage (`:input`, `:output`, or
`:tool`), the guardrail label, and the original `cause`.

- `Jidoka.chat/3` returns `{:error, %Jidoka.Error.ExecutionError{}}`.
- Pre-formatted Jidoka errors returned from a guardrail (`Jidoka.Error.*`) are
  passed through unchanged.
- `{:interrupt, ...}` returns surface as an interrupt notification on the
  agent and stop the turn at the guardrail boundary.
- Use [`Jidoka.format_error/1`](errors.md) for human output and
  [`Jidoka.inspect_agent/1`](inspection.md) to see the recorded guardrail
  metadata on the request.

## Guardrails Vs Hooks

[Hooks](hooks.md) shape a turn (rewrite messages, augment context, post-process
results). Guardrails block a turn: allow, interrupt, or refuse. Use a hook to
transform, a guardrail to enforce.

## See Also

- [hooks.md](hooks.md)
- [chat-turn.md](chat-turn.md)
- [errors.md](errors.md)
- [inspection.md](inspection.md)
- [imported-agents.md](imported-agents.md)

## Imported Agents

Imported JSON/YAML specs declare guardrails by published name under
`lifecycle.guardrails.{input,output,tool}`. Names resolve through the
`available_guardrails:` registry passed to `Jidoka.import_agent/2`. Modules
must implement the same `Jidoka.Guardrail` behaviour described above. See
[imported-agents.md](imported-agents.md) for the full spec format.
