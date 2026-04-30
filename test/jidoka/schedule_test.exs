defmodule JidokaTest.ScheduleTest do
  use JidokaTest.Support.Case, async: false

  alias Jidoka.Schedule
  alias JidokaTest.Workflow.ToolOnlyWorkflow

  setup do
    manager = :"schedule_manager_#{System.unique_integer([:positive])}"

    start_supervised!({Jidoka.Schedule.Manager, name: manager, id: manager, schedules: [], history_limit: 5})

    %{manager: manager}
  end

  test "exports public schedule APIs" do
    assert function_exported?(Jidoka, :schedule, 2)
    assert function_exported?(Jidoka, :schedule_agent, 2)
    assert function_exported?(Jidoka, :schedule_workflow, 2)
    assert function_exported?(Jidoka, :list_schedules, 1)
    assert function_exported?(Jidoka, :cancel_schedule, 2)
    assert function_exported?(Jidoka, :run_schedule, 2)
  end

  test "validates schedule options" do
    assert {:error, %Jidoka.Error.ValidationError{} = error} =
             Schedule.new(ToolOnlyWorkflow, kind: :workflow, id: "", cron: "* * * * *")

    assert error.field == :id

    assert {:error, %Jidoka.Error.ValidationError{} = error} =
             Schedule.new(ToolOnlyWorkflow, kind: :agent, id: "missing-prompt", cron: "* * * * *")

    assert error.field == :prompt
  end

  test "registers, lists, and cancels disabled schedules", %{manager: manager} do
    assert {:ok, %Schedule{id: "disabled-digest", status: :disabled, scheduler_pid: nil}} =
             Jidoka.schedule_workflow(ToolOnlyWorkflow,
               id: "disabled-digest",
               cron: "0 9 * * *",
               input: %{value: 5},
               enabled?: false,
               manager: manager
             )

    assert {:ok, [%Schedule{id: "disabled-digest"}]} = Jidoka.list_schedules(manager: manager)
    assert :ok = Jidoka.cancel_schedule("disabled-digest", manager: manager)
    assert {:ok, []} = Jidoka.list_schedules(manager: manager)
  end

  test "rejects duplicate schedule ids unless replaced", %{manager: manager} do
    opts = [
      id: "duplicate",
      cron: "0 9 * * *",
      input: %{value: 5},
      enabled?: false,
      manager: manager
    ]

    assert {:ok, %Schedule{}} = Jidoka.schedule_workflow(ToolOnlyWorkflow, opts)
    assert {:error, %Jidoka.Error.ValidationError{} = error} = Jidoka.schedule_workflow(ToolOnlyWorkflow, opts)
    assert error.message =~ "already registered"

    assert {:ok, %Schedule{id: "duplicate"}} =
             Jidoka.schedule_workflow(ToolOnlyWorkflow, Keyword.put(opts, :replace, true))
  end

  test "validates enabled cron expressions at registration time", %{manager: manager} do
    assert {:error, %Jidoka.Error.ValidationError{} = error} =
             Jidoka.schedule_workflow(ToolOnlyWorkflow,
               id: "bad-cron",
               cron: "not a cron",
               input: %{value: 5},
               manager: manager
             )

    assert error.field == :cron
  end

  test "runs a workflow schedule manually and records bounded history", %{manager: manager} do
    assert {:ok, %Schedule{id: "math-workflow"}} =
             Jidoka.schedule_workflow(ToolOnlyWorkflow,
               id: "math-workflow",
               cron: "0 9 * * *",
               input: %{value: 5},
               enabled?: false,
               manager: manager
             )

    assert {:ok, run} = Jidoka.run_schedule("math-workflow", manager: manager)
    assert run.status == :completed
    assert run.result == {:ok, %{value: 12}}
    assert is_binary(run.request_id)

    assert {:ok, [%Schedule{} = schedule]} = Jidoka.list_schedules(manager: manager)
    assert schedule.run_count == 1
    assert schedule.status == :disabled
    assert schedule.last_status == :completed
    assert hd(schedule.history).status == :completed
    refute Map.has_key?(hd(schedule.history), :result)

    assert {:ok, trace} = Jidoka.Trace.for_request(ToolOnlyWorkflow.id(), run.request_id)
    assert Enum.any?(trace.events, &(&1.category == :schedule and &1.event == :start))
    assert Enum.any?(trace.events, &(&1.category == :schedule and &1.event == :stop))
  end

  test "manual agent schedule failures are captured as failed runs", %{manager: manager} do
    assert {:ok, %Schedule{id: "missing-agent"}} =
             Jidoka.schedule_agent("missing-agent-id",
               id: "missing-agent",
               cron: "0 9 * * *",
               prompt: "Run a digest.",
               enabled?: false,
               manager: manager
             )

    assert {:ok, run} = Jidoka.run_schedule("missing-agent", manager: manager)
    assert run.status == :failed
    assert {:error, %Jidoka.Error.ValidationError{}} = run.result

    assert {:ok, [%Schedule{} = schedule]} = Jidoka.list_schedules(manager: manager)
    assert schedule.run_count == 1
    assert schedule.last_status == :failed
    assert schedule.last_error =~ "could not be found"
  end

  test "generated agents expose declared schedules" do
    assert [%Schedule{} = schedule] = JidokaTest.ScheduledAgent.schedules()

    assert schedule.id == "scheduled_agent:daily_digest"
    assert schedule.agent_id == "scheduled_agent:daily_digest"
    assert schedule.target == JidokaTest.ScheduledAgent
    assert schedule.cron == "0 9 * * *"
    assert schedule.timezone == "America/Chicago"
    assert schedule.conversation == "support-digest"
    assert schedule.overlap == :skip
  end
end
