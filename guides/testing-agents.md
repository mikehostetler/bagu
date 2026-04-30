# Testing Agents

Jidoka agents should be tested in layers. Most tests should not call a model.
The agent is useful because it combines deterministic code, runtime policy, and
an LLM turn. Test each layer separately, then add a small number of live evals
for provider behavior.

The example suite in `test/examples/agent_testing_walkthrough_test.exs` shows
these patterns against real example agents.

## The Testing Shape

Use this pyramid:

1. Contract tests: compiled DSL shape, tools, context defaults, output contract.
2. Unit tests: tools, guardrails, hooks, prompt builders, and pure helpers.
3. Provider-free integration tests: workflows, structured output finalization,
   imported specs, schedules, and runtime inspection.
4. Demo verification: `mix jidoka <example> --verify`.
5. Live evals: provider-backed behavior, tagged so normal CI does not call an
   LLM.

Avoid asserting exact natural-language model output in unit tests. Assert the
contracts around the model: tool calls, structured output, guardrails, trace
events, and domain outcomes.

## Contract Tests

Compiled agents expose stable helper functions. Use them to assert that the
agent is wired the way your application expects:

```elixir
test "support triage declares the expected public surface" do
  assert MyApp.SupportTriageAgent.id() == "support_triage_agent"
  assert MyApp.SupportTriageAgent.context() == %{tenant: "acme", channel: "support"}
  assert MyApp.SupportTriageAgent.tool_names() == ["load_ticket", "route_ticket"]
  assert MyApp.SupportTriageAgent.input_guardrails() == [MyApp.BlockPaymentSecrets]
  assert %Jidoka.Output{retries: 1} = MyApp.SupportTriageAgent.output()

  assert {:ok, inspection} = Jidoka.inspect_agent(MyApp.SupportTriageAgent)
  assert inspection.id == "support_triage_agent"
end
```

This catches accidental DSL drift before a chat turn starts.

## Tool Tests

Tools are deterministic modules. Test them directly:

```elixir
test "loads and routes a ticket" do
  assert {:ok, ticket} = MyApp.LoadTicket.run(%{ticket_id: "TCK-1001"}, %{})
  assert ticket.subject == "Duplicate invoice charge"

  assert {:ok, route} =
           MyApp.RouteTicket.run(%{category: :billing, priority: :high}, %{})

  assert route.route == :billing_ops
  assert route.escalation_required
end
```

Use these tests for domain logic, edge cases, and fixture coverage. The model
does not need to be involved.

## Guardrail And Hook Tests

Guardrails and hooks are ordinary modules. Build the input struct and call the
module directly:

```elixir
input = %Jidoka.Guardrails.Input{
  agent: MyApp.SupportTriageAgent.runtime_module().new(id: "guardrail-test"),
  server: self(),
  request_id: "req-guardrail-test",
  message: "Please use card 4242 4242 4242 4242.",
  context: %{},
  allowed_tools: nil,
  llm_opts: [],
  metadata: %{},
  request_opts: %{}
}

assert {:error, :payment_secret_detected} = MyApp.BlockPaymentSecrets.call(input)
```

This is the right layer for policy tests. Keep the assertions about allow,
block, interrupt, or transformed context.

## Structured Output Without A Provider

Structured output can be tested by simulating a completed request and finalizing
it:

```elixir
request_id = "output-test"

agent =
  MyApp.TicketClassifier.runtime_module().new(id: "ticket-classifier-test")
  |> Jido.AI.Request.start_request(request_id, "Classify this ticket.")
  |> Jido.AI.Request.complete_request(
    request_id,
    ~s({"category":"billing","confidence":0.97,"summary":"Duplicate charge."})
  )
  |> Jidoka.Output.finalize(request_id, MyApp.TicketClassifier.output())

assert {:ok, parsed} = Jido.AI.Request.get_result(agent, request_id)
assert parsed.category == :billing
```

Also test malformed output:

```elixir
output = %{MyApp.TicketClassifier.output() | retries: 0, on_validation_error: :error}

agent =
  MyApp.TicketClassifier.runtime_module().new(id: "ticket-classifier-bad-output")
  |> Jido.AI.Request.start_request(request_id, "Classify this ticket.")
  |> Jido.AI.Request.complete_request(request_id, ~s({"category":"legal"}))
  |> Jidoka.Output.finalize(request_id, output)

assert {:error, %Jidoka.Error.ValidationError{field: :output}} =
         Jido.AI.Request.get_result(agent, request_id)
```

This tests your contract and repair posture without spending tokens.

## Workflow Tests

Workflows are deterministic integration tests for tool wiring:

```elixir
test "math pipeline runs in order" do
  assert {:ok, %{value: 12}} = MyApp.MathPipeline.run(%{value: 5})

  assert {:error, %Jidoka.Error.ValidationError{}} =
           MyApp.MathPipeline.run(%{value: "not-an-integer"})
end
```

Use `return: :debug` when you need to assert step outputs or graph shape.

## Runtime Boundary Tests

Use process-level tests sparingly. They are most useful for checking that an
agent starts, can be discovered, emits traces, and obeys application lifecycle
rules:

```elixir
test "agent starts under the runtime" do
  id = "support-test-#{System.unique_integer([:positive])}"

  try do
    assert {:ok, pid} = MyApp.SupportTriageAgent.start_link(id: id)
    assert Jidoka.whereis(id) == pid
    assert {:ok, inspection} = Jidoka.inspect_agent(pid)
    assert inspection.id == id
  after
    Jidoka.stop_agent(id)
  end
end
```

Do not use this layer for domain logic that could be tested through tools or
structured output.

## Demo Verification

Every canonical example should have a provider-free verification path:

```bash
mix jidoka support_triage --verify
mix jidoka lead_qualification --verify
mix jidoka workflow
```

Use `--verify` to exercise example fixtures, deterministic tools, and structured
output finalization. Use `--dry-run --log-level trace` to inspect the compiled
agent configuration.

## Live Provider Tests

Keep live tests explicit and opt-in:

```elixir
@tag :llm_eval
test "routes a real ticket with the configured provider" do
  {:ok, pid} = MyApp.SupportTriageAgent.start_link(id: "support-live-test")

  try do
    assert {:ok, result} =
             MyApp.SupportTriageAgent.chat(pid, "Triage ticket TCK-1001.",
               context: %{tenant: "acme"},
               timeout: 60_000
             )

    assert result.category in [:billing, :technical, :account]
    assert is_binary(result.summary)
  after
    Jidoka.stop_agent(pid)
  end
end
```

Normal test runs exclude `:llm_eval`. Run live tests intentionally:

```bash
mix test --include llm_eval
```

## What To Avoid

- Do not make unit tests depend on exact LLM prose.
- Do not test private ReAct internals when a Jidoka public helper exists.
- Do not hide required context in test globals; pass `context:` explicitly.
- Do not let live provider tests run in normal CI by accident.
- Do not skip malformed-output tests for structured output agents.

The goal is confidence in the agent boundary: deterministic code is correct,
runtime policy is enforced, output contracts are stable, and live model behavior
is sampled where it matters.
