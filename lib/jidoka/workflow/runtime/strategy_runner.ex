defmodule Jidoka.Workflow.Runtime.StrategyRunner do
  @moduledoc false

  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.Runic.Directive.ExecuteRunnable
  alias Jido.Runic.{Introspection, Strategy}
  alias Jidoka.Workflow.Runtime.{Keys, Value}
  alias Runic.Workflow
  alias Runic.Workflow.Invokable

  @state_key Keys.state_key()

  @spec run(map(), map(), map(), Workflow.t()) :: {:ok, term()} | {:error, term()}
  def run(definition, state, runtime_opts, workflow) do
    agent = %Jido.Agent{
      id: "jidoka-workflow-#{definition.id}-#{System.unique_integer([:positive])}",
      name: definition.id,
      description: definition.description || "Jidoka workflow #{definition.id}",
      schema: [],
      state: %{}
    }

    strategy_context = %{agent_module: Jidoka.Workflow.StepAction, strategy_opts: [workflow: workflow]}
    {agent, []} = Strategy.init(agent, strategy_context)
    {agent, directives} = feed(agent, %{@state_key => state})
    deadline = System.monotonic_time(:millisecond) + runtime_opts.timeout

    with {:ok, agent, emitted} <- drain_strategy(definition, agent, directives, deadline) do
      strategy_state = StratState.get(agent)
      finish_run(definition, strategy_state, emitted, runtime_opts)
    end
  end

  defp feed(agent, data) do
    instruction = %Jido.Instruction{action: :runic_feed_signal, params: %{data: data}}
    Strategy.cmd(agent, [instruction], %{agent_module: Jidoka.Workflow.StepAction, strategy_opts: []})
  end

  defp apply_result(agent, runnable) do
    instruction = %Jido.Instruction{action: :runic_apply_result, params: %{runnable: runnable}}
    Strategy.cmd(agent, [instruction], %{agent_module: Jidoka.Workflow.StepAction, strategy_opts: []})
  end

  defp drain_strategy(definition, agent, directives, deadline),
    do: drain_strategy(definition, agent, directives, deadline, [])

  defp drain_strategy(_definition, agent, [], _deadline, emitted), do: {:ok, agent, Enum.reverse(emitted)}

  defp drain_strategy(definition, agent, [%ExecuteRunnable{} = directive | rest], deadline, emitted) do
    if System.monotonic_time(:millisecond) > deadline do
      {:error,
       Jidoka.Error.execution_error("Workflow execution timed out.",
         phase: :workflow,
         details: %{workflow_id: definition.id, reason: :timeout, cause: {:timeout, :deadline}}
       )}
    else
      runnable = Invokable.execute(directive.runnable.node, directive.runnable)

      case runnable.status do
        :completed ->
          {agent, next_directives} = apply_result(agent, runnable)
          drain_strategy(definition, agent, rest ++ next_directives, deadline, emitted)

        :failed ->
          {:error, runnable.error}

        other ->
          {:error,
           Jidoka.Error.execution_error("Workflow runnable did not complete.",
             phase: :workflow,
             details: %{workflow_id: definition.id, status: other, runnable_id: runnable.id, cause: other}
           )}
      end
    end
  end

  defp drain_strategy(definition, agent, [directive | rest], deadline, emitted) do
    if System.monotonic_time(:millisecond) > deadline do
      {:error,
       Jidoka.Error.execution_error("Workflow execution timed out.",
         phase: :workflow,
         details: %{workflow_id: definition.id, reason: :timeout, cause: {:timeout, :deadline}}
       )}
    else
      drain_strategy(definition, agent, rest, deadline, [directive | emitted])
    end
  end

  defp finish_run(definition, strategy_state, emitted, runtime_opts) do
    productions = Workflow.raw_productions(strategy_state.workflow)

    case {strategy_state.status, productions} do
      {:success, [_ | _]} ->
        final_state = Value.select_final_state(definition, productions)

        with {:ok, output} <- Value.resolve_value(definition.output, final_state) do
          case runtime_opts.return do
            :output ->
              {:ok, output}

            :debug ->
              {:ok,
               %{
                 workflow_id: definition.id,
                 status: strategy_state.status,
                 output: output,
                 steps: final_state.steps,
                 productions: productions,
                 emitted: emitted,
                 graph: Introspection.workflow_graph(strategy_state.workflow),
                 execution_summary: Introspection.execution_summary(strategy_state.workflow)
               }}
          end
        end

      {status, _} ->
        {:error,
         Jidoka.Error.execution_error("Workflow execution did not produce output.",
           phase: :workflow,
           details: %{workflow_id: definition.id, status: status, cause: status}
         )}
    end
  end
end
