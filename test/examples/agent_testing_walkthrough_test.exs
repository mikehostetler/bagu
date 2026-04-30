defmodule JidokaTest.Examples.AgentTestingWalkthroughTest do
  use JidokaTest.Support.Case, async: false

  setup_all do
    Enum.each(["support_triage", "lead_qualification", "structured_output", "workflow"], fn example ->
      assert {:ok, _module} = Jidoka.Demo.load(example)
    end)

    :ok
  end

  describe "compiled agent contracts" do
    test "support triage declares the expected public surface" do
      assert agent_id(support_agent()) == "support_triage_agent"
      assert agent_context(support_agent()) == %{tenant: "acme", channel: "support"}
      assert tool_names(support_agent()) == ["load_ticket", "route_ticket"]
      assert input_guardrails(support_agent()) == [payment_secret_guardrail()]

      assert %Jidoka.Output{retries: 1, on_validation_error: :repair} = agent_output(support_agent())
      assert {:ok, inspection} = Jidoka.inspect_agent(support_agent())
      assert inspection.id == "support_triage_agent"
      assert Enum.map(inspection.tools, &tool_name/1) == ["load_ticket", "route_ticket"]
    end

    test "lead qualification exposes typed context, tools, and output" do
      assert agent_context(lead_agent()) == %{territory: "na", source: "inbound"}
      assert tool_names(lead_agent()) == ["enrich_company", "score_lead"]
      assert %Jidoka.Output{} = agent_output(lead_agent())
    end
  end

  describe "deterministic tools" do
    test "support triage tools can be unit-tested without a model" do
      assert {:ok, ticket} = run_tool(load_ticket_tool(), %{ticket_id: "TCK-1001"})
      assert ticket.subject == "Duplicate invoice charge"

      assert {:ok, route} = run_tool(route_ticket_tool(), %{category: :billing, priority: :high})
      assert route.route == :billing_ops
      assert route.escalation_required

      assert {:error, {:unknown_ticket, "missing"}} = run_tool(load_ticket_tool(), %{ticket_id: "missing"})
    end

    test "lead qualification scoring is isolated from the agent turn" do
      assert {:ok, company} = run_tool(enrich_company_tool(), %{domain: "northwind.example"})
      assert company.company == "Northwind Finance"

      assert {:ok, score} = run_tool(score_lead_tool(), Map.take(company, [:employees, :recent_signal]))
      assert score.fit_score == 95
      assert score.segment == :enterprise
      assert score.intent == :high
      assert score.recommended_action == :solutions_engineer
    end
  end

  describe "lifecycle policy" do
    test "input guardrails are ordinary modules with direct tests" do
      safe = input_guardrail("Can you triage TCK-1001?")
      unsafe = input_guardrail("Please use card 4242 4242 4242 4242.")

      assert :ok = apply(payment_secret_guardrail(), :call, [safe])
      assert {:error, :payment_secret_detected} = apply(payment_secret_guardrail(), :call, [unsafe])
    end
  end

  describe "structured output without provider calls" do
    test "support triage output parses and coerces provider-like JSON" do
      assert {:ok, parsed} =
               finalize_output(
                 support_agent(),
                 ~s({"category":"billing","priority":"high","route":"billing_ops","needs_human":true,) <>
                   ~s("summary":"Northwind Finance reports a duplicate charge.",) <>
                   ~s("next_action":"Route to billing operations."})
               )

      assert parsed.category == :billing
      assert parsed.priority == :high
      assert parsed.route == :billing_ops
      assert parsed.needs_human
    end

    test "structured output tests should include malformed model output" do
      output = %{agent_output(ticket_classifier_agent()) | retries: 0, on_validation_error: :error}

      assert {:error, %Jidoka.Error.ValidationError{} = error} =
               finalize_output(
                 ticket_classifier_agent(),
                 ~s({"category":"legal","confidence":"very high","extra":"surprise"}),
                 output: output
               )

      assert error.field == :output
    end
  end

  describe "deterministic workflows" do
    test "workflow examples are integration tests for tool wiring" do
      assert {:ok, %{value: 12}} = run_workflow(math_pipeline(), %{value: 5})

      assert {:error, %Jidoka.Error.ValidationError{} = error} =
               run_workflow(math_pipeline(), %{value: "not-an-integer"})

      assert error.message =~ "Invalid workflow input"
    end
  end

  defp input_guardrail(message) do
    %Jidoka.Guardrails.Input{
      agent: runtime_module(support_agent()).new(id: "support-triage-guardrail-test"),
      server: self(),
      request_id: "req-guardrail-test",
      message: message,
      context: %{},
      allowed_tools: nil,
      llm_opts: [],
      metadata: %{},
      request_opts: %{}
    }
  end

  defp finalize_output(agent_module, raw, opts \\ []) do
    request_id = "example-output-#{System.unique_integer([:positive])}"
    output = Keyword.get(opts, :output, agent_output(agent_module))

    agent =
      runtime_module(agent_module).new(id: "#{agent_id(agent_module)}-output-test")
      |> Jido.AI.Request.start_request(request_id, "Return structured output.")
      |> Jido.AI.Request.complete_request(request_id, raw)
      |> Jidoka.Output.finalize(request_id, output)

    Jido.AI.Request.get_result(agent, request_id)
  end

  defp support_agent, do: Jidoka.Examples.SupportTriage.Agents.TriageAgent
  defp lead_agent, do: Jidoka.Examples.LeadQualification.Agents.LeadAgent
  defp ticket_classifier_agent, do: Jidoka.Examples.StructuredOutput.Agents.TicketClassifier
  defp math_pipeline, do: Jidoka.Examples.Workflow.Workflows.MathPipeline

  defp load_ticket_tool, do: Jidoka.Examples.SupportTriage.Tools.LoadTicket
  defp route_ticket_tool, do: Jidoka.Examples.SupportTriage.Tools.RouteTicket
  defp enrich_company_tool, do: Jidoka.Examples.LeadQualification.Tools.EnrichCompany
  defp score_lead_tool, do: Jidoka.Examples.LeadQualification.Tools.ScoreLead
  defp payment_secret_guardrail, do: Jidoka.Examples.SupportTriage.Guardrails.BlockPaymentSecrets

  defp agent_id(module), do: apply(module, :id, [])
  defp agent_context(module), do: apply(module, :context, [])
  defp agent_output(module), do: apply(module, :output, [])
  defp input_guardrails(module), do: apply(module, :input_guardrails, [])
  defp runtime_module(module), do: apply(module, :runtime_module, [])
  defp tool_names(module), do: apply(module, :tool_names, [])
  defp run_tool(module, params), do: apply(module, :run, [params, %{}])
  defp run_workflow(module, input), do: apply(module, :run, [input])

  defp tool_name(%{name: name}) when is_binary(name), do: name
  defp tool_name(module) when is_atom(module), do: apply(module, :name, [])
end
