# Hooks

Hooks are turn-scoped callbacks that run around a single Jidoka chat turn. Use
them to rewrite the user message, attach metadata, transform the final outcome,
or react to interrupts. Hooks are declared in the `lifecycle do` section and
resolved at compile time, so attachment is verified before the agent boots.

## Minimal Example

```elixir
defmodule MyApp.Hooks.AddTenant do
  use Jidoka.Hook, name: "add_tenant"

  @impl true
  def call(%Jidoka.Hooks.BeforeTurn{} = input) do
    tenant = Map.get(input.context, :tenant, "demo")

    {:ok,
     %{
       message: "#{input.message} for tenant #{tenant}",
       context: %{tenant: tenant},
       metadata: %{tenant_added?: true}
     }}
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
    before_turn MyApp.Hooks.AddTenant
  end
end
```

The hook fires on every `Jidoka.chat/3` call against this agent. See
[chat-turn.md](chat-turn.md) for how a turn is composed.

## Stages

Three stages are available. Each receives a different input struct and expects
its own return shape. Multiple hooks per stage are allowed.

### `before_turn`

Fires after request normalization and before the model or tools run. Receives a
`%Jidoka.Hooks.BeforeTurn{}` with `:agent`, `:request_id`, `:message`,
`:context`, `:allowed_tools`, `:llm_opts`, `:metadata`, and `:request_opts`.
Return one of:

- `{:ok, overrides}`: a map or keyword list whose keys are limited to
  `:message`, `:context`, `:allowed_tools`, `:llm_opts`, and `:metadata`.
  Overrides are merged into the in-flight turn.
- `{:interrupt, %Jidoka.Interrupt{}}`: short-circuits the turn. The request
  fails with the interrupt and any `on_interrupt` hooks fire.
- `{:error, reason}`: short-circuits the turn with a normalized
  `Jidoka.Error.ExecutionError`.

Hooks run in declaration order. The first hook that returns `:interrupt` or
`:error` halts the chain.

### `after_turn`

Fires once the runtime has produced an outcome. Receives a
`%Jidoka.Hooks.AfterTurn{}` with the same fields as `BeforeTurn` plus
`:outcome`, which is `{:ok, result}` or `{:error, reason}`. Return one of:

- `{:ok, {:ok, new_result}}` or `{:ok, {:error, new_reason}}`: replaces the
  recorded outcome. Use this to tag, redact, or rewrite results before they
  reach the caller.
- `{:interrupt, %Jidoka.Interrupt{}}`: marks the turn as interrupted and
  triggers `on_interrupt` hooks.
- `{:error, reason}`: replaces the outcome with a normalized execution error.

`after_turn` hooks run in reverse declaration order so the most recently added
hook wraps the others.

### `on_interrupt`

Fires after any interrupt raised by `before_turn`, `after_turn`, or the
runtime. Receives a `%Jidoka.Hooks.InterruptInput{}` that includes the
`%Jidoka.Interrupt{}` plus the same turn context.

Return `:ok`. The stage is notify-only: other return values are logged and
discarded, and these hooks cannot resume or replace the turn. Use them for
logging, telemetry, or external notifications. Hooks run in reverse
declaration order.

Each hook runs under a 5 second timeout. Timeouts and exceptions are converted
into stage-appropriate errors via [errors.md](errors.md).

## Defining Hook Modules

Hook modules opt in by `use Jidoka.Hook` and implement `call/1`:

```elixir
defmodule MyApp.Hooks.TagReply do
  use Jidoka.Hook, name: "tag_reply"

  @impl true
  def call(%Jidoka.Hooks.AfterTurn{outcome: {:ok, result}}) when is_binary(result) do
    {:ok, {:ok, "#{result} [checked]"}}
  end

  def call(%Jidoka.Hooks.AfterTurn{}), do: :ok
end
```

The `:name` option publishes the hook into registries used by imported agents
and tracing. If omitted, the underscored module basename is used. The
`Jidoka.Hook` behaviour requires `name/0` (provided automatically) and `call/1`
(yours).

Attach hooks in `lifecycle do`:

```elixir
lifecycle do
  before_turn MyApp.Hooks.AddTenant
  after_turn MyApp.Hooks.TagReply
  on_interrupt MyApp.Hooks.NotifyOnInterrupt
end
```

DSL hook refs accept a hook module or an `{module, function, args}` tuple.
Anonymous functions are not accepted in the DSL: extract them into a hook
module instead.

## Hooks vs Guardrails

Hooks shape the turn: they rewrite messages, decorate context, transform
outcomes, and observe interrupts. Guardrails decide whether the turn is allowed
to proceed at clearly defined input and output checkpoints. If the answer is
"block this," reach for a guardrail. If the answer is "adjust or react to
this," reach for a hook. See [guardrails.md](guardrails.md).

## Inspection

Generated agent modules expose `hooks/0` returning the resolved stage map:

```elixir
MyApp.SupportAgent.hooks()
#=> %{before_turn: [MyApp.Hooks.AddTenant], after_turn: [MyApp.Hooks.TagReply], on_interrupt: []}
```

The same data is available via [`Jidoka.inspect_agent/1`](inspection.md) under
the `:hooks` key, for both compiled and imported agents.

## See Also

- [guardrails.md](guardrails.md)
- [chat-turn.md](chat-turn.md)
- [inspection.md](inspection.md)
- [agents.md](agents.md)
- [imported-agents.md](imported-agents.md)

## Imported Agents

Imported JSON/YAML agents support hooks through the same `lifecycle.hooks`
block. Spec authors reference hooks by published name, and the host application
supplies the modules through an `available_hooks:` registry:

```json
{ "lifecycle": { "hooks": { "before_turn": ["add_tenant"] } } }
```

```elixir
{:ok, agent} = Jidoka.import_agent(json, available_hooks: [MyApp.Hooks.AddTenant])
```

Names must match each hook module's `name/0`. Unknown names are rejected at
import time. See [imported-agents.md](imported-agents.md) for registry rules.
