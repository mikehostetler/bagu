defmodule JidokaTest.MixTaskTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

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
