# Jidoka Gaps And Proposed Solutions

This document captures the main gaps surfaced while reviewing the Kitchen Sink
LiveBook and comparing Jidoka against modern agent framework expectations.

The short version: Jidoka already has a compelling authoring story. It can
compose tools, workflows, subagents, handoffs, context, memory, hooks,
guardrails, imported specs, AgentView, and LiveBook helpers. The missing layer is
runtime confidence: a developer needs to see, replay, resume, evaluate, and
safely operate a real agent run.

This is not a release-packaging checklist. It is a product and runtime-quality
checklist for sharpening Jidoka before moving it into the official organization.

## Comparison Baseline

Modern agent frameworks increasingly compete on these surfaces:

- OpenAI Agents SDK: first-class tracing spans for agents, model calls, tools,
  guardrails, handoffs, MCP, and response usage.
- LangGraph and LangSmith: durable execution, checkpoints, human-in-the-loop
  resume, time-travel debugging, trace trees, and graph visualization.
- Pydantic AI: typed inputs, typed outputs, validation, retries, and strong
  developer ergonomics around tool and output correctness.
- CrewAI: a clearer distinction between agent collaboration and deterministic
  flows, with stateful workflow composition.

Jidoka should not copy those APIs directly. Its advantage is an Elixir-native,
application-first layer over Jido and Jido.AI. The gaps below describe what
Jidoka needs so that advantage feels production-ready.

## Priority 1: First-Class Run Tracing

### What Is Missing

Jidoka currently has useful LiveBook debugging helpers, but it does not yet have
a durable trace model. Logs and summary tables are helpful while demoing, but
they are not enough to answer production questions:

- Which model call happened?
- Which tool was called, with what arguments?
- Which workflow steps ran?
- Which guardrail fired?
- Did a handoff transfer ownership?
- Which context keys were visible to the model or tool?
- How long did each step take?
- What failed, and where?

### Why It Matters

Text logs force users to reconstruct an agent run manually. Modern agent
debugging starts from a trace tree or timeline, not from raw logger output.

Without a trace model, every downstream feature becomes harder: LiveBook
inspection, AgentView debugging, eval replay, production observability,
handoff audits, and workflow visualization.

### Proposed Solution

Add a public runtime trace model:

```elixir
Jidoka.Trace.list(pid_or_agent, opts \\ [])
Jidoka.Trace.latest(pid_or_agent, opts \\ [])
Jidoka.Trace.get(pid_or_agent, run_id)
Jidoka.Trace.to_events(trace)
Jidoka.Trace.to_spans(trace)
```

Normalize these event/span types:

- `:run_start` and `:run_stop`
- `:agent_start` and `:agent_stop`
- `:model_start` and `:model_stop`
- `:tool_start` and `:tool_stop`
- `:workflow_start`, `:workflow_step`, and `:workflow_stop`
- `:subagent_start` and `:subagent_stop`
- `:handoff_start` and `:handoff_stop`
- `:guardrail_check` and `:guardrail_interrupt`
- `:memory_retrieve` and `:memory_capture`
- `:mcp_sync` and `:mcp_tool`
- `:error`

Add LiveBook helpers on top:

```elixir
Jidoka.Kino.timeline(pid_or_trace, opts \\ [])
Jidoka.Kino.call_graph(pid_or_trace, opts \\ [])
Jidoka.Kino.trace_table(pid_or_trace, opts \\ [])
```

### Alpha Acceptance

- A provider-backed Kitchen Sink chat can show a single coherent timeline.
- Tool, workflow, subagent, handoff, guardrail, memory, and error events appear
  in the same run view.
- Trace output is structured data first, Kino rendering second.

## Priority 2: Durable Execution And Resume

### What Is Missing

Jidoka supports interrupts and handoffs, but the user-facing model does not yet
feel durable. A developer needs a stable way to pause a run, inspect it, persist
it, resume it, and know what will or will not re-execute.

### Why It Matters

Human-in-the-loop agents are not just "return an interrupt." Real applications
need durable pending state. They need approval UIs, retries, audit trails, and
safe recovery after process restarts.

LangGraph sets a strong expectation here: execution can stop at a checkpoint and
later resume from that point.

### Proposed Solution

Introduce explicit run identity and resume semantics:

```elixir
Jidoka.run(agent_or_pid, input, run_id: "run_123", thread_id: "thread_456")
Jidoka.resume(agent_or_pid, run_id, decision)
Jidoka.pending(agent_or_pid, thread_id: "thread_456")
Jidoka.cancel(agent_or_pid, run_id)
```

Define durable records for:

- pending interrupts
- pending handoffs
- workflow step progress
- model/tool call results needed for replay
- visible conversation messages
- internal runtime context

Start with an in-memory adapter, but design the behavior around an adapter
contract:

```elixir
Jidoka.RunStore.Memory
Jidoka.RunStore.Ecto
```

### Alpha Acceptance

- A LiveBook can trigger an interrupt, render it, approve/reject/edit it, and
  resume the same run.
- The resume path is not a demo-only PID send.
- The package documents which operations are replayed and which are reused.

## Priority 3: Context Provenance And Visibility

### What Is Missing

`Jidoka.Kino.context/3` shows context, but it does not explain the runtime
boundary deeply enough. Advanced users need to know:

- where each key came from
- whether the key is public or internal
- whether the key was visible to the model
- whether the key was visible to tools
- whether the key was forwarded to subagents or handoffs
- whether memory modified the effective prompt
- how context changed during lifecycle hooks

### Why It Matters

Context is the control plane for agent behavior. If context is opaque, debugging
tool behavior, memory behavior, tenant isolation, handoffs, and prompt drift is
slow and error-prone.

### Proposed Solution

Add a context inspection model:

```elixir
Jidoka.Context.inspect(agent_or_pid, context, opts \\ [])
Jidoka.Context.diff(before_context, after_context, opts \\ [])
Jidoka.Context.visibility(agent_or_pid, context, opts \\ [])
```

Add Kino helpers:

```elixir
Jidoka.Kino.context_map(label, context, opts \\ [])
Jidoka.Kino.context_diff(label, before_context, after_context, opts \\ [])
```

The inspection should classify keys by visibility:

- `:public`
- `:internal`
- `:model_visible`
- `:tool_visible`
- `:subagent_forwarded`
- `:handoff_forwarded`
- `:memory_namespace`
- `:redacted`

### Alpha Acceptance

- The Kitchen Sink can show a context diff before and after lifecycle
  preparation.
- Subagent and handoff demos show exactly which keys are forwarded.
- Internal keys are visible in debug mode but clearly separated from app
  context.

## Priority 4: Runtime Workflow Visualization

### What Is Missing

The "workflow as a tool" feature is one of Jidoka's strongest ideas, but the
runtime inspection is still too static. The developer can inspect the workflow
definition, but they cannot easily see the exact runtime execution path.

### Why It Matters

Workflows are the deterministic counterpart to model reasoning. They should be
the easiest part of the system to inspect. If a workflow ran two steps in order,
the UI should show those two steps with inputs, outputs, timing, and status.

### Proposed Solution

Add step-level workflow trace data:

```elixir
Jidoka.inspect_workflow_run(run_id, workflow_name)
Jidoka.Workflow.trace(workflow_module, params, context, opts \\ [])
```

Expose workflow events in `Jidoka.Trace`.

Add Kino helpers:

```elixir
Jidoka.Kino.workflow_graph(workflow_module_or_run, opts \\ [])
Jidoka.Kino.workflow_steps(workflow_run, opts \\ [])
```

### Alpha Acceptance

- The workflow LiveBook shows both the static graph and a runtime execution
  table.
- Failed workflow steps show normalized errors and the failed input.
- Workflow-as-tool calls appear in the top-level agent trace.

## Priority 5: First-Class Structured Output

### What Is Missing

Jidoka emphasizes context schema and tool schemas, but structured final output is
not prominent enough. Modern users expect output validation to be a core agent
feature, not an advanced add-on.

### Why It Matters

Most production agents do not just chat. They classify, extract, route, draft,
decide, and return typed results. Typed output is also a natural place for retry
and self-correction behavior.

### Proposed Solution

Add an `output` DSL section:

```elixir
agent do
  output do
    schema Zoi.object(%{
      category: Zoi.string(),
      confidence: Zoi.float(),
      summary: Zoi.string()
    })

    retries 2
    on_validation_error :retry
  end
end
```

Mirror the feature in imported specs:

```json
{
  "output": {
    "schema": {
      "type": "object",
      "required": ["category", "confidence", "summary"]
    },
    "retries": 2
  }
}
```

### Alpha Acceptance

- README shows a simple typed output example.
- LiveBook includes one extraction/classification example.
- Validation errors are normalized and optionally sent back to the model for a
  retry.
- Imported agents can represent the same output contract safely.

## Priority 6: Guardrails As Policy

### What Is Missing

Jidoka has hooks and guardrails, but the API still feels closer to callback
plumbing than production policy. Developers need a clear way to express tool
permissions, approval requirements, redaction, and unsafe-action boundaries.

### Why It Matters

Modern agent apps often fail at the boundaries: web access, MCP tools, file
tools, financial actions, data writes, and tenant-sensitive data. Guardrails need
to be understandable before runtime and inspectable after runtime.

### Proposed Solution

Introduce a policy layer over guardrails:

```elixir
policy do
  approve tool: "send_invoice", when: [:external_effect]
  deny tool: "delete_account", unless: [:admin]
  redact [:api_key, :token, :ssn]
  allow_web domains: ["docs.example.com"]
end
```

Keep low-level guardrails available, but make policy the onboarding surface.

Policy checks should emit trace events:

- policy name
- decision
- reason
- affected tool or capability
- redacted fields

### Alpha Acceptance

- A LiveBook shows approve/edit/reject for a risky tool call.
- Policy decisions appear in the run trace.
- Policy can be tested without calling a provider.

## Priority 7: Memory Operational Contract

### What Is Missing

The Kitchen Sink shows memory across turns, but memory does not yet have enough
operational shape. Missing questions:

- What gets stored?
- When is it stored?
- How is it scoped by tenant, user, or session?
- How is it redacted?
- How is it expired?
- How can a developer inspect retrieved memories?
- How does memory affect replay?

### Why It Matters

Memory is useful, but it is also a risk surface. Users need to trust that memory
does not leak tenant data, silently alter behavior, or become impossible to
debug.

### Proposed Solution

Define a memory contract:

```elixir
memory do
  namespace {:context, :session}
  capture [:user_preferences, :case_summary]
  redact [:token, :secret]
  retention days: 30
end
```

Add inspection APIs:

```elixir
Jidoka.Memory.preview(agent_or_pid, context)
Jidoka.Memory.records(agent_or_pid, namespace)
Jidoka.Memory.clear(agent_or_pid, namespace)
```

### Alpha Acceptance

- LiveBook shows retrieved memory, captured memory, and the exact prompt text
  memory contributed.
- Memory namespaces are explicit and tenant-safe by default.
- Memory activity appears in `Jidoka.Trace`.

## Priority 8: Session And Chat Runtime UX

### What Is Missing

`Jidoka.Kino.chat/3` is useful for LiveBook demos, but Jidoka needs a clearer
runtime session surface for real applications:

- streaming events
- visible messages
- hidden/internal messages
- pending interrupts
- pending handoffs
- run state
- resume commands
- trace lookup

### Why It Matters

AgentView is the right boundary for UI integration, but the runtime needs a
canonical session shape behind it. Otherwise each application will invent its
own convention for pending state, visible history, context, and debugging.

### Proposed Solution

Introduce a session model:

```elixir
Jidoka.Session.start(agent_or_pid, opts \\ [])
Jidoka.Session.send(session, message, opts \\ [])
Jidoka.Session.stream(session, message, opts \\ [])
Jidoka.Session.resume(session, decision, opts \\ [])
Jidoka.Session.inspect(session)
```

Expose a stable state shape:

```elixir
%Jidoka.Session{
  id: "...",
  agent_id: "...",
  status: :idle | :running | :interrupted | :handed_off | :failed,
  visible_messages: [],
  pending: [],
  latest_run_id: "...",
  trace_id: "..."
}
```

### Alpha Acceptance

- AgentView can be backed by `Jidoka.Session`.
- Kino chat uses the same session surface.
- Provider chat, handoff, interrupt, and debug views all reference the same run
  and session IDs.

## Priority 9: Evals And Replay

### What Is Missing

The Kitchen Sink includes deterministic checks, but Jidoka does not yet have a
real eval story. Modern agent frameworks increasingly treat evals as part of
the development loop.

### Why It Matters

Agents regress in ways normal unit tests miss: wrong tool choice, missing
handoff, unsafe tool arguments, context leakage, invalid structured output, or
prompt drift. These need repeatable tests and trace-based replay.

### Proposed Solution

Add a lightweight eval module:

```elixir
Jidoka.Eval.case "routes billing disputes" do
  input "I need help with an invoice dispute"
  expect_tool "ks_billing_agent"
  expect_handoff to: "billing"
end
```

Support assertions for:

- tool choice
- workflow step sequence
- handoff target
- interrupt decision
- structured output
- context visibility
- memory retrieval
- trace shape

### Alpha Acceptance

- Evals can run without a provider when they test deterministic capabilities.
- Provider-backed evals can be marked separately.
- A trace from a failed eval can be rendered in LiveBook.

## Priority 10: Production MCP Posture

### What Is Missing

The fake MCP sync keeps LiveBooks portable, but production MCP needs a sharper
story:

- endpoint lifecycle
- auth and secrets
- tool naming collisions
- tool refresh
- tenant boundaries
- hosted versus local tools
- trace visibility
- policy controls

### Why It Matters

MCP expands the tool surface dramatically. Without strong namespacing,
inspection, and policy, it becomes hard to know what the model can actually do.

### Proposed Solution

Add a production MCP guide and runtime inspection:

```elixir
Jidoka.MCP.endpoints(agent_or_pid)
Jidoka.MCP.tools(agent_or_pid, endpoint: :filesystem)
Jidoka.MCP.refresh(agent_or_pid, endpoint: :filesystem)
Jidoka.MCP.policy(agent_or_pid)
```

MCP tools should appear in:

- agent diagrams
- trace events
- policy checks
- context visibility views

### Alpha Acceptance

- LiveBook has a real MCP chapter separate from the fake sync demo.
- Tool name conflicts are explained and tested.
- MCP calls are traceable and policy-checkable.

## Priority 11: Imported Agent Feature Parity

### What Is Missing

The imported-agent path is a first-class Jidoka surface, but richer DSL features
can easily drift away from the constrained JSON/YAML spec.

### Why It Matters

If imported agents lag too far behind the Elixir DSL, Jidoka effectively has two
products. The imported path should be constrained, but intentional.

### Proposed Solution

For each new feature, explicitly mark parity status:

- `:supported`
- `:unsupported_by_design`
- `:planned`
- `:elixir_only`

Expose this in inspection:

```elixir
Jidoka.inspect_agent(MyAgent, parity: true)
```

### Alpha Acceptance

- Output, policy, tracing metadata, and memory config all have an imported-spec
  story or an explicit documented exception.
- README and LiveBooks do not imply parity where it does not exist.

## Suggested Implementation Order

1. Add `Jidoka.Trace` as structured data.
2. Add `Jidoka.Kino.timeline/2` and `Jidoka.Kino.call_graph/2`.
3. Add context provenance and diff helpers.
4. Add workflow runtime tracing and workflow graph rendering.
5. Add first-class `output` DSL and imported-spec support.
6. Add durable run/session IDs and pending interrupt resume.
7. Add policy DSL over guardrails.
8. Add memory inspection and retention/redaction semantics.
9. Add eval cases with trace assertions.
10. Harden production MCP inspection and policy controls.

## Kitchen Sink LiveBook Follow-Up

The Kitchen Sink should remain an advanced walkthrough, but it should evolve
from "look at all the features" into "watch a real agent run."

The final version should have these runtime views:

- chat panel
- trace timeline
- call graph
- context visibility map
- workflow execution graph
- memory inspection table
- pending interrupt/handoff panel
- eval summary

That would make the LiveBook more than a demo. It would become the reference
debugging experience for Jidoka.
