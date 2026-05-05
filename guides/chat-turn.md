# Chat Turn Lifecycle

Every interaction with a Jidoka agent flows through `Jidoka.chat/3` (or the
generated `MyAgent.chat/3` helper). This guide describes the seven steps that
make up a single turn and the public return shapes you should match against.

## Minimal example

```elixir
{:ok, pid} = Jidoka.start_agent(MyApp.SupportAgent, id: "support-1")

case Jidoka.chat(pid, "How do I reset my password?", context: %{tenant: "acme"}) do
  {:ok, reply} -> reply
  {:interrupt, %Jidoka.Interrupt{} = interrupt} -> handle(interrupt)
  {:handoff, %Jidoka.Handoff{} = handoff} -> follow(handoff)
  {:error, reason} -> Jidoka.format_error(reason)
end
```

## The seven steps

A typical `Jidoka.chat/3` call performs these steps in order:

1. **Validate public options.** Jidoka checks `context:`, `conversation:`, and
   other documented keys. Internal keys like `tool_context:` are rejected.
2. **Route to the current handoff owner.** When the call carries a
   `conversation:` and that conversation has an active handoff owner, Jidoka
   forwards the turn to the owning agent.
3. **Resolve the target agent server.** Pids, registered names, and string ids
   are normalized to a live process.
4. **Parse and merge runtime context.** The incoming `context:` is parsed
   through the compiled Zoi schema (when one is declared) and merged with
   schema defaults.
5. **Apply runtime policy.** Character rendering, before-turn hooks, input
   guardrails, auto-compaction, memory capture and retrieval, MCP
   synchronization, and the per-tool generated context are layered onto the
   request.
6. **Send the request through Jido.AI.** The model is invoked with the
   composed prompt, tool catalog, and structured output settings.
7. **Normalize the response.** Interruptions, handoffs, errors, and successful
   completions are mapped to the public return shapes documented below.

## Context is not auto-projected

Raw `context:` is application data. The model only sees what instructions,
memory, skills, and tool descriptions expose. To make a context value visible
to the model, project it through dynamic instructions
(see [instructions.md](instructions.md)), a hook, a tool description, or a
memory inject step.

Compaction is also model-visible when enabled: Jidoka injects the latest
summary into the system prompt and trims only the provider-facing message
window. The original `Jido.Thread` remains intact. See
[compaction.md](compaction.md).

## Return shapes

Every chat call returns one of:

- `{:ok, value}`: the agent produced a reply (a string, or the parsed
  structured-output value when an `output do` block is declared).
- `{:interrupt, %Jidoka.Interrupt{}}`: a tool, hook, or guardrail paused the
  turn and is waiting for an outside response.
- `{:handoff, %Jidoka.Handoff{}}`: the agent transferred conversation
  ownership. Use `Jidoka.handoff_owner/1` and `Jidoka.reset_handoff/1` to
  inspect or clear the conversation routing.
- `{:error, %Jidoka.Error.ValidationError{}}`: bad public input (invalid
  options, context that fails the schema).
- `{:error, %Jidoka.Error.ConfigError{}}`: the agent or its dependencies are
  misconfigured (missing model, unreachable MCP endpoint, and so on).
- `{:error, %Jidoka.Error.ExecutionError{}}`: the turn started but failed
  during execution (tool crash, model error, dynamic resolver failure).

For the full breakdown of error classes, formatting with
`Jidoka.format_error/1`, and remediation guidance see [errors.md](errors.md).

## Inspecting a turn

Use `Jidoka.inspect_request/1` to see the composed request before it goes to
the model, and `Jidoka.inspect_agent/1` for static configuration. See
[inspection.md](inspection.md) for the full set of inspection helpers.

## See also

- [agents.md](agents.md): the DSL that drives the lifecycle.
- [instructions.md](instructions.md): how the system prompt is resolved in
  step 5.
- [context.md](context.md): how `context:` is parsed in step 4.
- [compaction.md](compaction.md): how long sessions are summarized before the
  provider call.
- [errors.md](errors.md): error class details for step 7.
- [inspection.md](inspection.md): debugging and tracing helpers.

## Imported agents

Imported JSON and YAML agents flow through the exact same lifecycle and the
same `Jidoka.chat/3` facade. They return the same shapes and surface the same
error classes. The only difference is where the agent definition came from.
See [imported-agents.md](imported-agents.md).
