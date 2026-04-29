defmodule JidokaTest.MixTaskTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  @canonical_examples [
    "support_triage",
    "lead_qualification",
    "data_analyst",
    "meeting_followup",
    "feedback_synthesizer",
    "invoice_extraction",
    "incident_triage",
    "approval_flow",
    "pr_reviewer",
    "research_brief",
    "document_intake"
  ]

  setup do
    previous_api_key = Application.get_env(:req_llm, :anthropic_api_key)
    Application.put_env(:req_llm, :anthropic_api_key, "test-key")

    on_exit(fn ->
      Jidoka.Runtime.debug(:off)
      Application.put_env(:req_llm, :anthropic_api_key, previous_api_key)
      Mix.Task.reenable("jidoka")
    end)

    :ok
  end

  test "chat demo mix task uses log-level in dry-run mode" do
    output =
      capture_io(fn ->
        Mix.Tasks.Jidoka.run(["chat", "--log-level", "debug", "--dry-run"])
      end)

    assert output =~ "Jidoka chat demo"
    assert output =~ "Log level: debug"
    assert output =~ "Dry run: no agent started."
    refute output =~ "Configured model:"
    refute output =~ "Tools:"
    assert Jidoka.Runtime.debug() == :off
  end

  test "imported demo mix task uses log-level in dry-run mode" do
    output =
      capture_io(fn ->
        Mix.Tasks.Jidoka.run(["imported", "--log-level", "debug", "--dry-run"])
      end)

    assert output =~ "Jidoka imported-agent demo"
    assert output =~ "Resolved model:"
    assert output =~ "Log level: debug"
    assert output =~ "Dry run: no agent started."
    refute output =~ "Spec file:"
    assert Jidoka.Runtime.debug() == :off
  end

  test "orchestrator demo mix task prints trace details in dry-run mode" do
    output =
      capture_io(fn ->
        Mix.Tasks.Jidoka.run(["orchestrator", "--log-level", "trace", "--dry-run"])
      end)

    assert output =~ "Jidoka orchestrator demo"
    assert output =~ "Log level: trace"
    assert output =~ "Debug status:"
    assert output =~ "Subagents"
    assert output =~ "research_agent"
    assert output =~ "writer_specialist"
    assert output =~ "Dry run: no agent started."
    assert Jidoka.Runtime.debug() == :off
  end

  test "workflow demo mix task prints workflow details in dry-run mode" do
    output =
      capture_io(fn ->
        Mix.Tasks.Jidoka.run(["workflow", "--log-level", "trace", "--dry-run"])
      end)

    assert output =~ "Jidoka workflow demo"
    assert output =~ "Workflow: math_pipeline"
    assert output =~ "Steps: add, double"
    assert output =~ "Dependencies:"
    assert output =~ "Dry run: workflow not executed."
    assert Jidoka.Runtime.debug() == :off
  end

  test "kitchen sink demo mix task prints showcase trace details in dry-run mode" do
    output =
      capture_io(fn ->
        Mix.Tasks.Jidoka.run(["kitchen_sink", "--log-level", "trace", "--dry-run"])
      end)

    assert output =~ "Jidoka kitchen sink demo"
    assert output =~ "Showcase only"
    assert output =~ "Runtime Context"
    assert output =~ "schema"
    assert output =~ "skills"
    assert output =~ "kitchen-guidelines"
    assert output =~ "mcp"
    assert output =~ ":local_fs as fs_*"
    assert output =~ "plugins"
    assert output =~ "showcase_plugin"
    assert output =~ "Subagents"
    assert output =~ "research_agent"
    assert output =~ "editor_specialist"
    assert output =~ "Dry run: no agent started."
    assert Jidoka.Runtime.debug() == :off
  end

  test "dynamic canonical examples are discoverable" do
    names = Jidoka.Demo.names()

    Enum.each(@canonical_examples, fn example ->
      assert example in names
    end)
  end

  test "support triage example verifies without a provider" do
    output =
      capture_io(fn ->
        Mix.Tasks.Jidoka.run(["support_triage", "--dry-run", "--log-level", "trace"])
      end)

    assert output =~ "Jidoka support triage example"
    assert output =~ "Runtime Context"
    assert output =~ "BlockPaymentSecrets"
    assert output =~ "Dry run: no agent started."
    assert Jidoka.Runtime.debug() == :off

    output =
      capture_io(fn ->
        Mix.Tasks.Jidoka.run(["support_triage", "--verify"])
      end)

    assert output =~ "Support triage verification: ok"
    assert output =~ "structured_output"
    assert Jidoka.Runtime.debug() == :off
  end

  test "lead qualification example verifies without a provider" do
    output =
      capture_io(fn ->
        Mix.Tasks.Jidoka.run(["lead_qualification", "--verify"])
      end)

    assert output =~ "Jidoka lead qualification example"
    assert output =~ "Lead qualification verification: ok"
    assert output =~ "structured_output"
    assert Jidoka.Runtime.debug() == :off
  end

  test "data analyst example verifies without a provider" do
    output =
      capture_io(fn ->
        Mix.Tasks.Jidoka.run(["data_analyst", "--verify"])
      end)

    assert output =~ "Jidoka data analyst example"
    assert output =~ "Data analyst verification: ok"
    assert output =~ "structured_output"
    assert Jidoka.Runtime.debug() == :off
  end

  test "remaining canonical examples verify without a provider" do
    examples = [
      {"meeting_followup", "Meeting follow-up verification: ok"},
      {"feedback_synthesizer", "Feedback synthesizer verification: ok"},
      {"invoice_extraction", "Invoice extraction verification: ok"},
      {"incident_triage", "Incident triage verification: ok"},
      {"approval_flow", "Approval flow verification: ok"},
      {"pr_reviewer", "PR reviewer verification: ok"},
      {"research_brief", "Research brief verification: ok"},
      {"document_intake", "Document intake verification: ok"}
    ]

    Enum.each(examples, fn {example, success_line} ->
      output =
        capture_io(fn ->
          Mix.Tasks.Jidoka.run([example, "--verify"])
        end)

      assert output =~ success_line
      assert output =~ "structured_output"
      assert Jidoka.Runtime.debug() == :off
    end)
  end

  test "trace demo mix task verifies structured tracing without a provider" do
    output =
      capture_io(fn ->
        Mix.Tasks.Jidoka.run(["trace", "--log-level", "trace", "--", "7"])
      end)

    assert output =~ "Jidoka trace smoke test"
    assert output =~ "Trace request:"
    assert output =~ "Trace categories:"
    assert output =~ "request"
    assert output =~ "model"
    assert output =~ "workflow"
    assert output =~ "Workflow output:"
    assert output =~ "Trace verification: ok"
    assert output =~ "Timeline:"
    assert Jidoka.Runtime.debug() == :off
  end

  test "trace demo supports dry-run mode" do
    output =
      capture_io(fn ->
        Mix.Tasks.Jidoka.run(["trace", "--dry-run"])
      end)

    assert output =~ "Jidoka trace smoke test"
    assert output =~ "Dry run: trace smoke test not executed."
    assert Jidoka.Runtime.debug() == :off
  end

  test "chat demo enters the repl immediately with no scripted prompts" do
    output =
      capture_io("exit\n", fn ->
        Mix.Tasks.Jidoka.run(["chat"])
      end)

    assert output =~ "Jidoka chat demo"
    assert output =~ "Type `exit` or press Ctrl-D to quit."
    assert output =~ "Try: Add 8 and 13."
    refute output =~ "Running memory demo:"
    refute output =~ "Running tool guardrail demo:"
    assert Jidoka.Runtime.debug() == :off
  end

  test "orchestrator demo enters the repl immediately with no scripted prompts" do
    output =
      capture_io("exit\n", fn ->
        Mix.Tasks.Jidoka.run(["orchestrator"])
      end)

    assert output =~ "Jidoka orchestrator demo"
    assert output =~ "Type `exit` or press Ctrl-D to quit."
    refute output =~ "Running orchestration demo:"
    assert Jidoka.Runtime.debug() == :off
  end

  test "invalid log-level fails clearly" do
    assert_raise Mix.Error, ~r/invalid --log-level "loud".*info, debug, trace/, fn ->
      Mix.Tasks.Jidoka.run(["chat", "--log-level", "loud", "--dry-run"])
    end
  end
end
