defmodule Jido.Tools.Workflow do
  @moduledoc """
  A specialized Action type that executes a sequence of workflow steps.

  This Workflow is intentinoally simplistic - it is not meant to replace more mature Workflow
  libraries that exist in the Elixir ecosystem.  It is included for basic use cases relevant to
  the Jido project.

  This module extends `Jido.Action` with workflow capabilities, allowing
  you to define a sequence of steps to be executed in order. Each step
  follows the Elixir AST pattern of `{:atom, metadata, params}`.

  ## Supported Step Types

  - `{:step, metadata, [instruction]}` - Execute a single instruction
  - `{:branch, metadata, [condition_value, true_action, false_action]}` - Conditional branching
  - `{:converge, metadata, [instruction]}` - Converge branch paths
  - `{:parallel, metadata, [instructions]}` - Execute instructions in parallel

  ## Parallel Step Metadata

  Parallel steps support the following metadata options:

  - `:max_concurrency` - Maximum number of parallel tasks (default: scheduler count)
  - `:timeout_ms` - Timeout per parallel task in milliseconds (default: `:infinity`, compatibility mode)
  - `:fail_on_error` - When `true`, any parallel error fails the workflow step. Defaults to `false`
    for backwards compatibility, in which case errors are returned as `%{error: ...}` entries in
    `parallel_results`.

  ## Usage

  ```elixir
  defmodule MyWorkflow do
    use Jido.Tools.Workflow,
      name: "my_workflow",
      description: "A workflow that performs multiple steps",
      steps: [
        {:step, [name: "step_1"], [{LogAction, message: "Step 1"}]},
        {:branch, [name: "branch_1"], [
          true,  # This will typically be replaced at runtime with a dynamic value
          {:step, [name: "true_branch"], [{LogAction, message: "Greater than 10"}]},
          {:step, [name: "false_branch"], [{LogAction, message: "Less than or equal to 10"}]}
        ]},
        {:step, [name: "final_step"], [{LogAction, message: "Completed"}]}
      ]
  end
  ```

  ## Handling Dynamic Conditions

  For branch conditions that need to be evaluated at runtime, override the `execute_step/3`
  function in your module to handle the specific branch condition check:

  ```elixir
  # Override execute_step to handle a specific branch condition
  def execute_step({:branch, [name: "my_condition"], [_placeholder, true_branch, false_branch]}, params, context) do
    # Determine condition dynamically using params
    condition_value = params.value > 10

    # Choose the branch based on the condition value
    if condition_value do
      execute_step(true_branch, params, context)
    else
      execute_step(false_branch, params, context)
    end
  end

  # Fall back to the default implementation for other steps
  def execute_step(step, params, context) do
    super(step, params, context)
  end
  ```
  """

  alias Jido.Action.Error

  # Valid step types
  @valid_step_types [:step, :branch, :converge, :parallel]

  # Custom validation function for workflow steps
  @doc false
  def validate_step(steps) when is_list(steps) do
    # Simple validation to check that steps are tuples with the right format
    valid_steps =
      Enum.all?(steps, fn
        {step_type, metadata, _params} when is_atom(step_type) and is_list(metadata) ->
          step_type in @valid_step_types

        _ ->
          false
      end)

    if valid_steps, do: {:ok, steps}, else: {:error, "invalid workflow steps format"}
  end

  @doc false
  def validate_step(_), do: {:error, "steps must be a list of tuples"}

  # Schema for validating workflow configuration
  @workflow_config_schema NimbleOptions.new!(
                            workflow: [
                              type: {:custom, __MODULE__, :validate_step, []},
                              required: true,
                              doc: """
                              List of workflow steps to execute. Each step follows the Elixir AST pattern
                              of `{:atom, metadata, params}`. Supported step types:

                              - `:step` - Execute a single instruction
                              - `:branch` - Conditional branching based on a boolean value
                              - `:converge` - Converge branch paths
                              - `:parallel` - Execute instructions in parallel
                              """
                            ]
                          )

  @doc """
  Callback for executing a single workflow step.

  Takes a step tuple, parameters, and context and returns the result.
  """
  @callback execute_step(step :: tuple(), params :: map(), context :: map()) ::
              {:ok, map()} | {:error, any()}

  # Make the callback optional
  @optional_callbacks [execute_step: 3]

  @doc """
  Macro for setting up a module as a Workflow with step execution capabilities.
  """
  @spec __using__(keyword()) :: Macro.t()
  defmacro __using__(opts) do
    escaped_schema = Macro.escape(@workflow_config_schema)
    valid_step_types = @valid_step_types

    quote location: :keep do
      # Separate WorkflowAction-specific options from base Action options
      workflow_keys = [:workflow]
      workflow_opts = Keyword.take(unquote(opts), workflow_keys)
      action_opts = Keyword.drop(unquote(opts), workflow_keys)

      # Store valid step types
      @valid_step_types unquote(valid_step_types)

      # Validate WorkflowAction-specific options
      case NimbleOptions.validate(workflow_opts, unquote(escaped_schema)) do
        {:ok, validated_workflow_opts} ->
          @behaviour Jido.Tools.Workflow

          use Jido.Action, action_opts

          alias Jido.Tools.Workflow.Execution

          # Store validated workflow options for later use - steps will be stored as module attribute
          @workflow_steps validated_workflow_opts[:workflow]

          # Add workflow flag
          @workflow true

          # Pass the remaining options to the base Action

          # Implement the behavior

          # Implement the run function that executes the workflow
          @impl Jido.Action
          def run(params, context) do
            # Execute the workflow steps sequentially
            Execution.execute_workflow(@workflow_steps, params, context, __MODULE__)
          end

          # Add workflow-specific functionality
          @doc "Returns true if this module is a workflow."
          @spec workflow?() :: boolean()
          def workflow?, do: @workflow

          @doc "Returns the workflow steps for this module."
          @spec workflow_steps() :: list()
          def workflow_steps, do: @workflow_steps

          # Make to_json overridable before redefining it
          defoverridable to_json: 0

          @doc "Returns the workflow metadata as JSON including workflow flag and steps."
          @spec to_json() :: map()
          def to_json do
            # Get the base JSON from Jido.Action
            base_json = super()
            # Add workflow flag and steps to the result
            base_json
            |> Map.put(:workflow, @workflow)
            |> Map.put(:steps, @workflow_steps)
          end

          # Make to_tool overridable before redefining it
          defoverridable to_tool: 0

          @doc "Converts the workflow to an LLM-compatible tool format."
          @spec to_tool() :: map()
          def to_tool do
            tool = super()

            # Map keys can be atoms or strings, standardize on strings
            # Also rename parameters_schema to parameters for compatibility
            tool
            |> Map.new(fn
              {k, v} when is_atom(k) -> {Atom.to_string(k), v}
              entry -> entry
            end)
            |> Map.put("parameters", Map.get(tool, "parameters_schema", %{}))
          end

          @doc """
          Default implementation for executing a workflow step.

          Handles step, branch, converge, and parallel step types.
          """
          @spec execute_step(tuple(), map(), map()) :: {:ok, any()} | {:error, any()}
          def execute_step(step, params, context) do
            Execution.execute_step(step, params, context, __MODULE__)
          end

          # Allow execute_step to be overridden
          defoverridable execute_step: 3

        {:error, error} ->
          message = Error.format_nimble_config_error(error, "WorkflowAction", __MODULE__)
          raise CompileError, description: message, file: __ENV__.file, line: __ENV__.line
      end
    end
  end
end
