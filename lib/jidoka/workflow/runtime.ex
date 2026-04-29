defmodule Jidoka.Workflow.Runtime do
  @moduledoc false

  alias Jido.Runic.ActionNode
  alias Jidoka.Workflow.Runtime.{Keys, Options, StepRunner, StrategyRunner, Value}
  alias Runic.Workflow

  @definition_key Keys.definition_key()
  @step_key Keys.step_key()
  @state_key Keys.state_key()
  @runner_key Keys.runner_key()

  @type definition :: map()
  @type state :: %{
          input: map(),
          context: map(),
          agents: map(),
          steps: map(),
          workflow_id: String.t(),
          timeout: non_neg_integer()
        }

  @doc false
  @spec state_key() :: atom()
  def state_key, do: Keys.state_key()

  @doc false
  @spec build_workflow(definition()) :: Workflow.t()
  def build_workflow(%{id: id, steps: steps, dependencies: dependencies} = definition) do
    Enum.reduce(steps, Workflow.new(name: id), fn step, workflow ->
      node = action_node(definition, step)

      case Map.fetch!(dependencies, step.name) do
        [] -> Workflow.add(workflow, node, validate: :off)
        parents -> Workflow.add(workflow, node, to: parents, validate: :off)
      end
    end)
  end

  @doc false
  @spec inspect_definition(definition()) :: map()
  def inspect_definition(%{kind: :workflow_definition} = definition) do
    %{
      kind: :workflow_definition,
      id: definition.id,
      module: definition.module,
      description: definition.description,
      input_schema: definition.input_schema,
      steps: inspect_steps(definition),
      dependencies: definition.dependencies,
      output: definition.output
    }
  end

  @doc false
  @spec run(definition(), map() | keyword(), keyword()) :: {:ok, term()} | {:error, term()}
  def run(%{kind: :workflow_definition} = definition, input, opts) when is_list(opts) do
    result =
      with {:ok, runtime_opts} <- Options.normalize(opts),
           {:ok, parsed_input} <- Options.parse_input(definition, input),
           :ok <- Options.validate_runtime_refs(definition, runtime_opts) do
        state = Options.initial_state(definition, parsed_input, runtime_opts)
        workflow = build_workflow(definition)
        StrategyRunner.run(definition, state, runtime_opts, workflow)
      end

    case result do
      {:error, reason} ->
        {:error, Jidoka.Error.Normalize.workflow_error(reason, workflow_id: definition.id)}

      other ->
        other
    end
  end

  @doc false
  @spec run_step(map(), map()) :: {:ok, map()} | {:error, term()}
  def run_step(params, _context) when is_map(params) do
    definition = Map.fetch!(params, @definition_key)
    step = Map.fetch!(params, @step_key)
    state = Value.extract_state!(params)

    case StepRunner.execute_step(definition, step, state) do
      {:ok, result} ->
        updated_state = put_in(state, [:steps, step.name], result)
        {:ok, %{@state_key => updated_state}}

      {:error, reason} ->
        {:error, StepRunner.step_error(definition, step, reason)}
    end
  end

  defp action_node(definition, step) do
    ActionNode.new(
      Jidoka.Workflow.StepAction,
      %{
        @definition_key => definition,
        @step_key => step,
        @runner_key => {__MODULE__, :run_step}
      },
      name: step.name,
      inputs: [{@state_key, [type: :any, doc: "Jidoka workflow runtime state"]}],
      outputs: [{@state_key, [type: :any, doc: "Jidoka workflow runtime state"]}],
      timeout: 0,
      log_level: :warning,
      max_retries: 0
    )
  end

  defp inspect_steps(definition) do
    Enum.map(definition.steps, fn step ->
      %{
        name: step.name,
        kind: step.kind,
        target: step.target,
        dependencies: Map.fetch!(definition.dependencies, step.name)
      }
    end)
  end
end
