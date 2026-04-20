defmodule MotoTest.MixTaskTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  setup do
    previous_api_key = Application.get_env(:req_llm, :anthropic_api_key)
    Application.put_env(:req_llm, :anthropic_api_key, "test-key")

    on_exit(fn ->
      Moto.Runtime.debug(:off)
      Application.put_env(:req_llm, :anthropic_api_key, previous_api_key)
      Mix.Task.reenable("moto")
    end)

    :ok
  end

  test "chat demo mix task uses log-level in dry-run mode" do
    output =
      capture_io(fn ->
        Mix.Tasks.Moto.run(["chat", "--log-level", "debug", "--dry-run"])
      end)

    assert output =~ "Moto chat demo"
    assert output =~ "Log level: debug"
    assert output =~ "Dry run: no agent started."
    refute output =~ "Configured model:"
    refute output =~ "Tools:"
    assert Moto.Runtime.debug() == :off
  end

  test "orchestrator demo mix task prints trace details in dry-run mode" do
    output =
      capture_io(fn ->
        Mix.Tasks.Moto.run(["orchestrator", "--log-level", "trace", "--dry-run"])
      end)

    assert output =~ "Moto orchestrator demo"
    assert output =~ "Log level: trace"
    assert output =~ "Debug status:"
    assert output =~ "Subagents: research_agent, writer_specialist"
    assert output =~ "Dry run: no agent started."
    assert Moto.Runtime.debug() == :off
  end

  test "chat demo enters the repl immediately with no scripted prompts" do
    output =
      capture_io("exit\n", fn ->
        Mix.Tasks.Moto.run(["chat"])
      end)

    assert output =~ "Moto chat demo"
    assert output =~ "Type `exit` or press Ctrl-D to quit."
    assert output =~ "Try: Add 8 and 13."
    refute output =~ "Running memory demo:"
    refute output =~ "Running tool guardrail demo:"
    assert Moto.Runtime.debug() == :off
  end

  test "orchestrator demo enters the repl immediately with no scripted prompts" do
    output =
      capture_io("exit\n", fn ->
        Mix.Tasks.Moto.run(["orchestrator"])
      end)

    assert output =~ "Moto orchestrator demo"
    assert output =~ "Type `exit` or press Ctrl-D to quit."
    refute output =~ "Running orchestration demo:"
    assert Moto.Runtime.debug() == :off
  end

  test "invalid log-level fails clearly" do
    assert_raise Mix.Error, ~r/invalid --log-level "loud".*info, debug, trace/, fn ->
      Mix.Tasks.Moto.run(["chat", "--log-level", "loud", "--dry-run"])
    end
  end
end
