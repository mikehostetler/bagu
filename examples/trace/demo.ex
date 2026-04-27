defmodule Jidoka.Examples.Trace.Tools.AddOne do
  @moduledoc false

  use Jidoka.Tool,
    name: "trace_add_one",
    description: "Adds one to a value.",
    schema: Zoi.object(%{value: Zoi.integer()})

  @impl true
  def run(%{value: value}, _context), do: {:ok, %{value: value + 1}}
end

defmodule Jidoka.Examples.Trace.Tools.DoubleValue do
  @moduledoc false

  use Jidoka.Tool,
    name: "trace_double_value",
    description: "Doubles a value.",
    schema: Zoi.object(%{value: Zoi.integer()})

  @impl true
  def run(%{value: value}, _context), do: {:ok, %{value: value * 2}}
end

defmodule Jidoka.Examples.Trace.Workflows.MathPipeline do
  @moduledoc false

  use Jidoka.Workflow

  workflow do
    id :trace_math_pipeline
    description "Adds one, then doubles the result."
    input Zoi.object(%{value: Zoi.integer()})
  end

  steps do
    tool :add, Jidoka.Examples.Trace.Tools.AddOne, input: %{value: input(:value)}
    tool :double, Jidoka.Examples.Trace.Tools.DoubleValue, input: from(:add)
  end

  output from(:double)
end

defmodule Jidoka.Examples.Trace.Agents.WorkflowAgent do
  @moduledoc false

  use Jidoka.Agent

  agent do
    id :trace_demo_agent
  end

  defaults do
    model :fast
    instructions "Use deterministic workflows for known math operations."
  end

  capabilities do
    workflow(Jidoka.Examples.Trace.Workflows.MathPipeline,
      as: :trace_math_pipeline,
      result: :structured
    )
  end
end

defmodule Jidoka.Examples.Trace.Demo do
  @moduledoc false

  alias Jidoka.Demo.CLI

  @required_categories [:request, :model, :workflow]

  @spec main([String.t()]) :: :ok
  def main(argv) do
    CLI.run_command(argv, "trace", fn -> :ok end, &run/2)
  end

  @spec usage() :: :ok
  def usage, do: CLI.usage("trace")

  defp run(options, log_level) do
    IO.puts("Jidoka trace smoke test")
    CLI.print_log_status(log_level)

    if options.dry_run? do
      IO.puts("Dry run: trace smoke test not executed.")
    else
      value = parse_value!(options.prompt || "5")
      trace = run_trace!(value)
      print_trace(trace, log_level)
      verify_trace!(trace)
      IO.puts("Trace verification: ok")
    end

    :ok
  end

  defp run_trace!(value) do
    request_id = "req-trace-smoke-#{System.unique_integer([:positive])}"
    run_id = "run-trace-smoke-#{System.unique_integer([:positive])}"
    agent_id = "trace-smoke-agent"

    emit_request_start(agent_id, request_id, run_id)
    emit_model_complete(agent_id, request_id, run_id)

    tool = workflow_tool()

    {:ok, %{output: output}} =
      tool.run(%{value: value}, %{
        Jidoka.Subagent.server_key() => self(),
        Jidoka.Subagent.request_id_key() => request_id,
        Jidoka.Trace.agent_id_key() => agent_id,
        tenant: "trace-demo"
      })

    emit_request_complete(agent_id, request_id, run_id)
    wait_for_collector()

    case Jidoka.inspect_trace(agent_id, request_id) do
      {:ok, trace} ->
        %{trace | summary: Map.put(trace.summary, :workflow_output, output)}

      {:error, reason} ->
        raise Mix.Error, message: "trace smoke test failed: #{Jidoka.format_error(reason)}"
    end
  end

  defp emit_request_start(agent_id, request_id, run_id) do
    :telemetry.execute(
      [:jido, :ai, :request, :start],
      %{},
      %{
        agent_id: agent_id,
        request_id: request_id,
        run_id: run_id,
        jido_trace_id: "trace-#{request_id}",
        jido_span_id: "span-#{request_id}",
        query: "synthetic smoke-test prompt"
      }
    )
  end

  defp emit_model_complete(agent_id, request_id, run_id) do
    :telemetry.execute(
      [:jido, :ai, :llm, :complete],
      %{duration_ms: 7, input_tokens: 4, output_tokens: 2},
      %{
        agent_id: agent_id,
        request_id: request_id,
        run_id: run_id,
        model: "demo:model",
        llm_call_id: "llm-smoke"
      }
    )
  end

  defp emit_request_complete(agent_id, request_id, run_id) do
    :telemetry.execute(
      [:jido, :ai, :request, :complete],
      %{duration_ms: 12},
      %{agent_id: agent_id, request_id: request_id, run_id: run_id}
    )
  end

  defp print_trace(trace, log_level) do
    categories =
      trace.events
      |> Enum.map(& &1.category)
      |> Enum.uniq()
      |> Enum.map(&Atom.to_string/1)
      |> Enum.join(", ")

    IO.puts("Trace request: #{trace.request_id}")
    IO.puts("Trace status: #{trace.status}")
    IO.puts("Trace events: #{length(trace.events)}")
    IO.puts("Trace categories: #{categories}")
    IO.puts("Workflow output: #{inspect(trace.summary.workflow_output)}")

    if log_level == :trace do
      IO.puts("")
      IO.puts("Timeline:")

      Enum.each(trace.events, fn event ->
        IO.puts(
          "  ##{event.seq} #{event.category}.#{event.event} " <>
            "name=#{event.name || "-"} status=#{event.status || "-"} duration_ms=#{event.duration_ms || "-"}"
        )
      end)
    end
  end

  defp verify_trace!(trace) do
    categories = trace.events |> Enum.map(& &1.category) |> MapSet.new()
    missing = Enum.reject(@required_categories, &MapSet.member?(categories, &1))

    if missing != [] do
      raise Mix.Error, message: "trace smoke test missed categories: #{Enum.join(missing, ", ")}"
    end

    :ok
  end

  defp wait_for_collector do
    Process.sleep(25)
  end

  defp workflow_tool do
    Enum.find(Jidoka.Examples.Trace.Agents.WorkflowAgent.tools(), fn tool ->
      tool.name() == "trace_math_pipeline"
    end)
  end

  defp parse_value!(value) do
    value
    |> String.trim()
    |> Integer.parse()
    |> case do
      {integer, ""} ->
        integer

      _other ->
        raise Mix.Error, message: "trace demo expects an integer input, got: #{inspect(value)}"
    end
  end
end
