# Compaction

Jidoka compaction is opt-in lifecycle policy for long-running conversations.
It summarizes older turns, keeps the original `Jido.Thread` intact, and trims
only the provider-facing message window for future turns.

Use compaction when a session can accumulate enough history to make provider
context expensive, slow, or noisy, but you still want the running agent process
to retain the full conversation thread for inspection and application logic.

## Configure Compaction

Declare compaction inside `lifecycle do`:

```elixir
defmodule MyApp.SupportAgent do
  use Jidoka.Agent

  agent do
    id :support_agent
  end

  defaults do
    model :fast
    instructions "Help support agents resolve customer tickets."
  end

  lifecycle do
    compaction do
      mode :auto
      strategy :summary
      max_messages 40
      keep_last 12
      max_summary_chars 4_000
    end
  end
end
```

No `compaction do` block means unchanged behavior. Jidoka never compacts a
conversation unless the agent opts in.

## Modes

- `:auto`: compact automatically before a turn when the projected messages
  exceed `max_messages`.
- `:manual`: compact only when application code calls `Jidoka.compact/2`.
- `:off`: keep the config present but disabled.

V1 supports only `strategy :summary`.

## What Gets Sent To The Model

When compaction runs, Jidoka:

1. reads the projected conversation messages through `Jidoka.Agent.View`
2. summarizes messages older than the retained tail
3. stores the latest compaction snapshot on the running agent state
4. injects the summary into the next system prompt
5. sends only the retained tail, preserving tool-call and tool-result
   adjacency at the boundary

The original thread remains available through AgentView and inspection. This is
not a transcript store and not durable persistence.

## Default Prompt

If `prompt` is omitted, Jidoka uses a built-in summarizer prompt designed to
preserve the user's active goal, decisions, constraints, facts, tool outcomes,
handoffs, guardrails, errors, open questions, and next steps. It also asks the
summarizer not to include secrets or irrelevant raw logs.

You can override the prompt with a static string:

```elixir
compaction do
  max_messages 30
  keep_last 10
  prompt "Summarize the support conversation for the next agent turn."
end
```

Or with a module:

```elixir
defmodule MyApp.SupportCompactionPrompt do
  @behaviour Jidoka.Compaction.Prompt

  @impl true
  def build_compaction_prompt(input) do
    """
    Summarize this support thread for tenant #{input.context.tenant}.
    Preserve ticket ids, commitments, blockers, and the next best action.
    Return only summary text.
    """
  end
end
```

```elixir
compaction do
  prompt MyApp.SupportCompactionPrompt
end
```

MFA prompt builders are also accepted:

```elixir
compaction do
  prompt {MyApp.Prompts, :support_compaction, [:enterprise]}
end
```

Jidoka calls MFA prompts as `support_compaction(input, :enterprise)`.

## Manual Compaction

For manual mode, or for explicit operator controls, call `Jidoka.compact/2`:

```elixir
session =
  Jidoka.Session.new!(
    agent: MyApp.SupportAgent,
    id: "support-123",
    context: %{tenant: "acme"}
  )

{:ok, _reply} = Jidoka.chat(session, "Here is the long ticket history...")

{:ok, compaction} = Jidoka.compact(session)
```

`compact/2` accepts a session, running pid, registered agent id, or `%Jido.Agent{}`
snapshot. Sessions must already have a running agent.

## Inspection

Read the latest compaction snapshot with:

```elixir
{:ok, compaction} = Jidoka.inspect_compaction(session)
```

The snapshot is a `%Jidoka.Compaction{}` with stable fields such as
`:status`, `:summary_preview`, `:source_message_count`,
`:retained_message_count`, `:request_id`, `:started_at_ms`, and
`:completed_at_ms`.

Request summaries also include bounded metadata under `:jidoka_compaction`
when compaction was evaluated during the turn.

## Tracing And Livebook

Compaction emits trace events in category `:compaction`:

- `:start`
- `:summarized`
- `:skipped`
- `:error`

In Livebook, use:

```elixir
Jidoka.Kino.compaction(session)
Jidoka.Kino.timeline(session)
Jidoka.Kino.call_graph(session)
```

`Jidoka.Kino.compaction/2` renders the latest snapshot as a small table. The
trace helpers show when compaction ran relative to hooks, guardrails, memory,
tools, workflows, and provider calls.

## Testing

Use the application override to make tests provider-free:

```elixir
setup do
  old = Application.get_env(:jidoka, :compaction_summarizer)

  Application.put_env(:jidoka, :compaction_summarizer, fn input ->
    {:ok, "Summary of #{input.source_message_count} older messages."}
  end)

  on_exit(fn ->
    if is_nil(old) do
      Application.delete_env(:jidoka, :compaction_summarizer)
    else
      Application.put_env(:jidoka, :compaction_summarizer, old)
    end
  end)
end
```

Then assert on `Jidoka.inspect_compaction/2`, `Jidoka.inspect_request/2`, or
trace events.

## Imported Agents

Imported JSON/YAML agents use the portable `lifecycle.compaction` shape:

```json
{
  "lifecycle": {
    "compaction": {
      "mode": "auto",
      "strategy": "summary",
      "max_messages": 40,
      "keep_last": 12,
      "max_summary_chars": 4000,
      "prompt": "Summarize this conversation for future turns."
    }
  }
}
```

Only static string prompts are portable through JSON/YAML. Module and MFA
prompt builders are available in the Elixir DSL.

## See Also

- [sessions.md](sessions.md): stable multi-turn addressing.
- [memory.md](memory.md): durable-ish conversational recall via `jido_memory`.
- [chat-turn.md](chat-turn.md): where compaction runs in the turn lifecycle.
- [tracing.md](tracing.md): structured event visibility.
- [inspection.md](inspection.md): request and runtime snapshots.
