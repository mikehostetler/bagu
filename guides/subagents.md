# Subagents

A subagent is another Jidoka agent exposed to a parent agent as a tool. The
parent stays in control of the conversation and delegates one bounded task to a
specialist, then decides how to use the returned result.

Reach for a subagent when the parent should ask "who can help me answer this?"
and still own the final reply. For deterministic ordered processing use a
[workflow](workflows.md). To transfer ownership of future turns to another
agent use a [handoff](handoffs.md).

## Minimal Example

```elixir
capabilities do
  subagent MyApp.ResearchAgent,
    as: :research_agent,
    description: "Ask the research specialist for concise notes.",
    target: :ephemeral,
    forward_context: {:only, [:tenant, :session]},
    result: :structured
end
```

The parent model now sees a `research_agent` tool. Calling it runs
`MyApp.ResearchAgent` for one task and returns its reply to the parent's tool
loop.

## Options

The `subagent` capability accepts these keys:

- `as:` published tool name. Defaults to the child agent's id.
- `description:` tool description shown to the parent model. Defaults to the
  child agent's description.
- `target:` delegation mode. One of:
  - `:ephemeral` (default): start a fresh child process per call and stop it
    afterward.
  - `{:peer, "agent-id"}`: delegate to a long-lived peer agent already started
    under that id.
  - `{:peer, {:context, :key}}`: resolve the peer id from the parent's runtime
    context under `key`.
- `timeout:` child delegation timeout in milliseconds. Defaults to `30_000`.
- `forward_context:` context forwarding policy. One of `:public` (default),
  `:none`, `{:only, [keys]}`, or `{:except, [keys]}`.
- `result:` parent-visible result shape. `:text` (default) returns the child's
  final string. `:structured` returns the child's structured output payload
  when the child agent declares an `output_schema`.

## When To Use Which

```diagram
╭──────────────────────────────╮  ╭──────────────────────╮  ╭────────────────────────╮
│ Ask a specialist this turn   │  │ Run an ordered job   │  │ Transfer future turns  │
│ subagent                     │  │ workflow             │  │ handoff                │
│ Parent stays in control      │  │ App owns the steps   │  │ Conversation moves     │
╰──────────────────────────────╯  ╰──────────────────────╯  ╰────────────────────────╯
```

Use a subagent when:

- The parent should pick when and whether to delegate.
- The work fits in one bounded request (research, summarize, rewrite).
- The parent will compose the final answer from the result.

Avoid subagents when the application already knows the steps (use a
[workflow](workflows.md)) or when the user should keep talking to a different
agent on the next turn (use a [handoff](handoffs.md)).

## See Also

- [agents.md](agents.md): the underlying agent shape that subagents reuse.
- [workflows.md](workflows.md): deterministic step-by-step orchestration.
- [handoffs.md](handoffs.md): conversation ownership transfer.
- [tools.md](tools.md): how parent-visible capabilities surface as tools.
- [overview.md](overview.md): the orchestration decision matrix.

## Imported Agents

JSON/YAML imported agents declare subagents under
`capabilities.subagents`, and the application supplies the resolvable child
modules through `available_subagents:`:

```elixir
Jidoka.import_agent(json,
  available_subagents: [MyApp.ResearchAgent]
)
```

When a compiled Elixir manager needs to delegate to a JSON/YAML-authored
specialist, use `Jidoka.ImportedAgent.Subagent` as the agent module. See
[imported-agents.md](imported-agents.md) for the full subagent spec.
