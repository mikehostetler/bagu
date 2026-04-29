# Structured Output

Jidoka agents can return validated, structured maps instead of free text.
Declare a Zoi object schema inside `agent do output do ... end end` and
`chat/3` returns the parsed map. This is the right shape for classifiers,
extractors, routers, and any agent whose result feeds into downstream code.

## Minimal Example

```elixir
defmodule MyApp.TicketClassifier do
  use Jidoka.Agent

  agent do
    id :ticket_classifier

    output do
      schema Zoi.object(%{
        category: Zoi.enum([:billing, :technical, :account]),
        confidence: Zoi.float(),
        summary: Zoi.string()
      })
    end
  end

  defaults do
    model :fast
    instructions "Classify support tickets for routing."
  end
end
```

```elixir
{:ok, ticket} = MyApp.TicketClassifier.chat(pid, "Card declined again.")
ticket.category   #=> :billing
ticket.confidence #=> 0.92
```

Jidoka attaches a JSON Schema rendered from the Zoi schema to the model call,
parses the model response, and validates it before returning.

## The `output do` Block

The block lives inside `agent do` and accepts three keys:

```elixir
agent do
  id :my_agent

  output do
    schema Zoi.object(%{...})
    retries 1
    on_validation_error :repair
  end
end
```

- `schema`: required. A Zoi object/map schema describing the final response.
- `retries`: optional. Number of repair attempts when the model returns
  invalid output. Defaults to `1`. Values above `3` are capped.
- `on_validation_error`: optional. One of:
  - `:repair` (default): on validation failure, Jidoka makes a single
    structured-object follow-up call to coerce the response into the schema.
  - `:error`: skip repair and return a validation error directly.

Repair uses the agent's own model by default. Without a model in scope, repair
fails with `Invalid output: cannot repair without a model.`

## Per-Turn Raw Opt-Out

To bypass structured output for a single call, pass `output: :raw`:

```elixir
{:ok, text} = MyApp.TicketClassifier.chat(pid, "What is your favourite color?",
  output: :raw
)
```

The model response is returned without schema parsing or repair. The
declarative `output do` contract is unchanged for other turns.

## Validation Failure Shape

When validation (and any allowed repair) fails, Jidoka returns a tagged
`ValidationError`:

```elixir
{:error, %Jidoka.Error.ValidationError{} = err} =
  MyApp.TicketClassifier.chat(pid, "...")

Jidoka.format_error(err)
#=> "Invalid output: output did not match the configured schema. ..."
```

The struct carries diagnostic detail in `details`:

- `details.reason`: a tagged tuple such as `{:schema, errors}`,
  `{:parse, message}`, `:expected_map`, or `{:repair_failed, message}`.
- `details.raw_preview`: a truncated preview of the raw model output, useful
  for log-friendly debugging without dumping the full response.
- `field: :output`: marks the validation site.

Use `Jidoka.format_error/1` for a human-readable message and inspect
`details.reason` programmatically when you need to branch.

## Tracing

Each structured-output attempt emits a trace event under the `:output`
category with the request id, schema kind, attempt number, and outcome
(`:start`, `:repair`, `:validated`, `:error`). See
[tracing.md](tracing.md) for how to attach a handler.

## See also

- [agents.md](agents.md)
- [chat-turn.md](chat-turn.md)
- [errors.md](errors.md)
- [tracing.md](tracing.md)
- [models.md](models.md)

## Imported agents

Imported JSON/YAML agents support structured output through a top-level
`output` block in the spec, using a JSON Schema object for `schema` plus the
same `retries` and `on_validation_error` knobs. The Zoi-only authoring path is
specific to the compiled DSL: imported specs must use a JSON Schema object
because Zoi schemas are not portable across the JSON/YAML format. See
[imported-agents.md](imported-agents.md).
