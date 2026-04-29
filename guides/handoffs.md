# Handoffs

A handoff transfers ownership of a `conversation:` from one Jidoka agent to
another. Future turns sent against the same conversation id route to the new
owner. The handoff is returned to the caller as a first-class
`%Jidoka.Handoff{}` value rather than buried in a tool reply.

Use a handoff when the user should keep talking to a different agent on the
next turn. For one-shot specialist delegation that the parent still owns, use
a [subagent](subagents.md). For deterministic ordered processing use a
[workflow](workflows.md).

## Minimal Example

Declare the handoff capability on the source agent:

```elixir
capabilities do
  handoff MyApp.BillingAgent,
    as: :transfer_billing_ownership,
    description: "Transfer ongoing billing ownership to billing.",
    target: :auto,
    forward_context: {:only, [:tenant, :session, :account_id]}
end
```

Call chat with a `conversation:` id. When the model invokes the handoff tool,
the chat returns a `{:handoff, ...}` tuple instead of a reply:

```elixir
{:handoff, %Jidoka.Handoff{} = handoff} =
  Jidoka.chat(router_pid, "Billing should own this from here.",
    conversation: "support-123",
    context: %{tenant: "acme", account_id: "acct_123"}
  )
```

The next call against `"support-123"` automatically routes to the new owner:

```elixir
Jidoka.chat(router_pid, "What is the next billing step?",
  conversation: "support-123"
)
```

## Capability Options

The `handoff` capability accepts:

- `as:` published tool name. Defaults to the target agent's id.
- `description:` tool description shown to the source model. Defaults to the
  target agent's description, or `"Transfer conversation to <name>."`.
- `target:` ownership routing mode. One of:
  - `:auto` (default): start or reuse a deterministic owner for the current
    conversation.
  - `{:peer, "agent-id"}`: hand off to a long-lived peer agent already started
    under that id.
  - `{:peer, {:context, :key}}`: resolve the peer id from the source agent's
    runtime context under `key`.
- `forward_context:` context forwarding policy. One of `:public` (default),
  `:none`, `{:only, [keys]}`, or `{:except, [keys]}`.

## Handoff Tool Fields

Jidoka generates a tool the source model can call. Its arguments are:

- `message` (required): the user-facing message to carry into the new agent.
- `summary` (optional): a short summary of what was discussed.
- `reason` (optional): why the handoff was issued.

These flow into `%Jidoka.Handoff{}` as `:message`, `:summary`, and `:reason`.
The struct also carries `:from_agent`, `:to_agent`, `:to_agent_id`,
`:conversation_id`, and the forwarded `:context`.

## Inspecting And Resetting Ownership

```elixir
Jidoka.handoff_owner("support-123")
# => {:ok, MyApp.BillingAgent} | {:ok, nil}

Jidoka.reset_handoff("support-123")
# => :ok
```

`Jidoka.handoff_owner/1` returns the current owner module for a conversation,
or `nil` if no handoff has occurred. `Jidoka.reset_handoff/1` clears ownership
so the next call routes to the original entry agent.

## Handoff vs Subagent

Both expose another agent to the source model as a tool. The difference is who
owns the next turn:

- A subagent runs once and returns a result to the parent. The parent stays in
  control. Use it for "ask a specialist this turn."
- A handoff changes the conversation owner. The next chat with the same
  `conversation:` id is answered by the new owner. Use it for "the user should
  keep talking to billing now."

A subagent reply is a normal `{:ok, value}`. A handoff result is a
`{:handoff, %Jidoka.Handoff{}}` tuple your application is expected to act on
(notify the user, log the transfer, etc.).

## See Also

- [subagents.md](subagents.md): one-shot specialist delegation.
- [workflows.md](workflows.md): deterministic ordered processing.
- [chat-turn.md](chat-turn.md): how `Jidoka.chat/3` returns and `conversation:`
  routing.
- [context.md](context.md): how `forward_context` controls what crosses the
  boundary.
- [errors.md](errors.md): handoff-related error shapes.

## Imported Agents

JSON/YAML imported agents declare handoffs under `capabilities.handoffs`, and
the application supplies the resolvable target modules through
`available_handoffs:`:

```elixir
Jidoka.import_agent(json,
  available_handoffs: [MyApp.BillingAgent]
)
```

`target: "auto"` mirrors the compiled `:auto` mode. `"peer"` targets require
either `peer_id` or `peer_id_context_key`. See
[imported-agents.md](imported-agents.md) for the full handoff spec.
