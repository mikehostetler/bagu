defmodule Jido.Plan do
  @moduledoc """
  Plans define DAGs (Directed Acyclic Graphs) of Instructions using keyword lists or builder methods.

  A Plan is a struct that can be built up using various methods and then normalized
  into a directed graph of Instructions for execution.

  ## Simple Sequential Plan

      plan = Plan.new()
      |> Plan.add(:fetch, MyApp.FetchAction)
      |> Plan.add(:validate, MyApp.ValidateAction, depends_on: :fetch)
      |> Plan.add(:save, MyApp.SaveAction, depends_on: :validate)

  ## Plan with Parameters

      plan = Plan.new()
      |> Plan.add(:fetch, {MyApp.FetchAction, %{source: "api"}})
      |> Plan.add(:validate, {MyApp.ValidateAction, %{strict: true}}, depends_on: :fetch)
      |> Plan.add(:save, {MyApp.SaveAction, %{destination: "/tmp"}}, depends_on: :validate)

  ## Plan with Parallel Steps

      plan = Plan.new()
      |> Plan.add(:fetch_users, MyApp.FetchUsersAction)
      |> Plan.add(:fetch_orders, MyApp.FetchOrdersAction)
      |> Plan.add(:fetch_products, MyApp.FetchProductsAction)
      |> Plan.add(:merge, MyApp.MergeAction, depends_on: [:fetch_users, :fetch_orders, :fetch_products])

  ## From Keyword Lists

      plan_def = [
        fetch: MyApp.FetchAction,
        validate: {MyApp.ValidateAction, depends_on: :fetch},
        save: {MyApp.SaveAction, %{dest: "/tmp"}, depends_on: :validate}
      ]

      {:ok, plan} = Plan.build(plan_def)

  Plans can be normalized into a directed graph for execution analysis and validation.
  """

  alias Jido.Action.Error
  alias Jido.Instruction

  @type step_def ::
          module()
          | {module(), map()}
          | {module(), keyword()}
          | {module(), map(), keyword()}
          | Instruction.t()

  defmodule PlanInstruction do
    @moduledoc """
    A single step in the execution plan.

    Only contains plan-level metadata. Execution metadata like retry, timeout, etc.
    should go in the Instruction.opts field.
    """

    # Define Zoi schema for PlanInstruction
    @schema Zoi.struct(
              __MODULE__,
              %{
                id:
                  Zoi.string(description: "Unique plan instruction identifier")
                  |> Zoi.optional(),
                name: Zoi.atom(description: "Step name"),
                instruction: Zoi.any(description: "Instruction struct"),
                depends_on:
                  Zoi.list(Zoi.atom(), description: "List of step dependencies")
                  |> Zoi.default([]),
                opts:
                  Zoi.list(Zoi.any(), description: "Additional options")
                  |> Zoi.default([])
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))

    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)
  end

  # Define Zoi schema for Plan
  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Zoi.string(description: "Unique plan identifier") |> Zoi.optional(),
              steps:
                Zoi.map(description: "Map of step names to PlanInstructions")
                |> Zoi.default(%{}),
              context: Zoi.map(description: "Shared execution context") |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc """
  Creates a new empty Plan struct.

  ## Examples

      iex> Plan.new()
      %Plan{steps: %{}}

      iex> Plan.new(context: %{user_id: "123"})
      %Plan{context: %{user_id: "123"}}
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      id: Uniq.UUID.uuid7(),
      steps: %{},
      context: Keyword.get(opts, :context, %{})
    }
  end

  @doc """
  Creates a Plan from a keyword list definition.

  ## Parameters
    * `plan_def` - Keyword list defining the plan structure
    * `context` - Optional context map (default: %{})

  ## Returns
    * `{:ok, %Plan{}}` - Successfully created plan
    * `{:error, term()}` - If plan definition is invalid

  ## Examples

      iex> plan_def = [
      ...>   fetch: MyApp.FetchAction,
      ...>   validate: {MyApp.ValidateAction, depends_on: :fetch}
      ...> ]
      iex> {:ok, plan} = Plan.build(plan_def)
      {:ok, %Plan{...}}
  """
  @spec build(keyword(), map()) :: {:ok, t()} | {:error, term()}
  def build(plan_def, context \\ %{}) when is_list(plan_def) do
    if Keyword.keyword?(plan_def) do
      do_build_plan(plan_def, context)
    else
      {:error, Error.validation_error("Plan must be a keyword list", %{got: plan_def})}
    end
  end

  defp do_build_plan(plan_def, context) do
    plan = new(context: context)

    Enum.reduce_while(plan_def, {:ok, plan}, &reduce_step/2)
  end

  defp reduce_step({step_name, step_def}, {:ok, acc_plan}) do
    case add_step_from_def(acc_plan, step_name, step_def) do
      {:ok, updated_plan} -> {:cont, {:ok, updated_plan}}
      {:error, _} = error -> {:halt, error}
    end
  end

  @doc """
  Same as build/3 but raises on error.
  """
  @spec build!(keyword(), map()) :: t() | no_return()
  def build!(plan_def, context \\ %{}) do
    case build(plan_def, context) do
      {:ok, plan} -> plan
      {:error, error} -> raise error
    end
  end

  @doc """
  Adds a single instruction to the plan.

  ## Parameters
    * `plan` - The plan to add to
    * `step_name` - Atom name for the step
    * `step_def` - Step definition (action module, tuple, or instruction)
    * `opts` - Optional keyword list with :depends_on and other options

  ## Examples

      iex> plan = Plan.new()
      iex> plan = Plan.add(plan, :fetch, MyApp.FetchAction)
      iex> plan = Plan.add(plan, :save, MyApp.SaveAction, depends_on: :fetch)
  """
  @spec add(t(), atom(), step_def(), keyword()) :: t() | no_return()
  def add(%__MODULE__{} = plan, step_name, step_def, opts \\ []) do
    {clean_step_def, step_depends_on} = extract_depends_on_from_step_def(step_def)
    opts_depends_on = opts |> Keyword.get(:depends_on, []) |> List.wrap()
    depends_on = (step_depends_on ++ opts_depends_on) |> Enum.uniq()

    plan_opts = Keyword.delete(opts, :depends_on)

    # Validate depends_on contains only atoms
    if !Enum.all?(depends_on, &is_atom/1) do
      error = Error.validation_error("All dependencies must be atoms", %{depends_on: depends_on})
      raise error
    end

    case Instruction.normalize_single(clean_step_def, plan.context, []) do
      {:ok, instruction} ->
        plan_instruction = %PlanInstruction{
          id: Uniq.UUID.uuid7(),
          name: step_name,
          instruction: instruction,
          depends_on: depends_on,
          opts: plan_opts
        }

        %{plan | steps: Map.put(plan.steps, step_name, plan_instruction)}

      {:error, _error} ->
        error = Error.validation_error("Invalid instruction format", %{step_def: step_def})
        raise error
    end
  end

  @doc """
  Adds dependencies between steps.

  ## Parameters
    * `plan` - The plan to update
    * `step_name` - Step to add dependencies to
    * `deps` - Single dependency or list of dependencies

  ## Examples

      iex> plan = Plan.new()
      iex> |> Plan.add(:step1, Action1)
      iex> |> Plan.add(:step2, Action2)
      iex> |> Plan.depends_on(:step2, :step1)
  """
  @spec depends_on(t(), atom(), atom() | [atom()]) :: t() | no_return()
  def depends_on(%__MODULE__{} = plan, step_name, deps) do
    case Map.get(plan.steps, step_name) do
      nil ->
        error = Error.validation_error("Step not found", %{step_name: step_name})
        raise error

      plan_instruction ->
        current_deps = plan_instruction.depends_on
        new_deps = (current_deps ++ List.wrap(deps)) |> Enum.uniq()
        updated_instruction = %{plan_instruction | depends_on: new_deps}

        %{plan | steps: Map.put(plan.steps, step_name, updated_instruction)}
    end
  end

  @doc """
  Normalizes the Plan into a directed graph and list of PlanInstructions.

  ## Returns
    * `{:ok, {graph, plan_instructions}}` - Graph and list of plan instructions
    * `{:error, term()}` - If normalization fails

  ## Examples

      iex> plan = Plan.new() |> Plan.add(:step1, MyAction)
      iex> {:ok, {graph, plan_instructions}} = Plan.normalize(plan)
      iex> [%Plan.PlanInstruction{name: :step1}] = plan_instructions
  """
  @spec normalize(t()) :: {:ok, {Graph.t(), [PlanInstruction.t()]}} | {:error, term()}
  def normalize(%__MODULE__{} = plan) do
    plan_instructions = Map.values(plan.steps)

    with :ok <- validate_defined_dependencies(plan_instructions),
         {:ok, graph} <- build_graph(plan_instructions),
         :ok <- validate_graph(graph) do
      {:ok, {graph, plan_instructions}}
    end
  end

  @doc """
  Same as normalize/1 but raises on error.
  """
  @spec normalize!(t()) :: {Graph.t(), [PlanInstruction.t()]} | no_return()
  def normalize!(%__MODULE__{} = plan) do
    case normalize(plan) do
      {:ok, result} -> result
      {:error, error} -> raise error
    end
  end

  @doc """
  Returns the execution phases for the plan (topological sort).

  ## Examples

      iex> plan = Plan.new() |> Plan.add(:step1, Action1)
      iex> {:ok, phases} = Plan.execution_phases(plan)
      {:ok, [[:step1]]}
  """
  @spec execution_phases(t()) :: {:ok, [[atom()]]} | {:error, term()}
  def execution_phases(%__MODULE__{} = plan) do
    with {:ok, {graph, _plan_instructions}} <- normalize(plan) do
      phases = Graph.topsort(graph) |> build_execution_phases(graph)
      {:ok, phases}
    end
  end

  @doc """
  Converts the plan back to a keyword list format.
  """
  @spec to_keyword(t()) :: keyword()
  def to_keyword(%__MODULE__{} = plan) do
    plan.steps
    |> Enum.map(fn {step_name, plan_instruction} ->
      step_def = instruction_to_step_def(plan_instruction.instruction)

      formatted_def =
        case plan_instruction.depends_on do
          [] -> step_def
          deps -> add_depends_on_to_step_def(step_def, deps)
        end

      {step_name, formatted_def}
    end)
    |> Enum.sort_by(fn {step_name, _} -> step_name end)
  end

  # Private helper functions

  defp add_step_from_def(plan, step_name, step_def) do
    case extract_depends_on_from_step_def(step_def) do
      {clean_step_def, depends_on} ->
        {:ok, add(plan, step_name, clean_step_def, depends_on: depends_on)}
    end
  rescue
    error -> {:error, error}
  end

  defp extract_depends_on_from_step_def(step_def) do
    case step_def do
      {action, opts} when is_atom(action) and is_list(opts) ->
        depends_on = Keyword.get(opts, :depends_on, [])
        clean_opts = Keyword.delete(opts, :depends_on)
        clean_step_def = if clean_opts == [], do: action, else: {action, clean_opts}
        {clean_step_def, depends_on}

      {action, params, opts} when is_atom(action) and is_map(params) and is_list(opts) ->
        depends_on = Keyword.get(opts, :depends_on, [])
        clean_opts = Keyword.delete(opts, :depends_on)

        clean_step_def =
          if clean_opts == [], do: {action, params}, else: {action, params, clean_opts}

        {clean_step_def, depends_on}

      _ ->
        {step_def, []}
    end
  end

  defp validate_defined_dependencies(plan_instructions) do
    defined_steps =
      plan_instructions
      |> Enum.map(& &1.name)
      |> MapSet.new()

    missing_dependencies_by_step =
      Enum.reduce(plan_instructions, %{}, fn plan_instruction, acc ->
        missing_dependencies =
          plan_instruction.depends_on
          |> Enum.uniq()
          |> Enum.reject(&MapSet.member?(defined_steps, &1))
          |> Enum.sort()

        if missing_dependencies == [] do
          acc
        else
          Map.put(acc, plan_instruction.name, missing_dependencies)
        end
      end)

    if map_size(missing_dependencies_by_step) == 0 do
      :ok
    else
      {:error,
       Error.validation_error("Plan contains dependencies on undefined steps", %{
         missing_dependencies_by_step: missing_dependencies_by_step,
         available_steps: defined_steps |> MapSet.to_list() |> Enum.sort()
       })}
    end
  end

  defp build_graph(plan_instructions) do
    graph = Graph.new(type: :directed)

    # Add all vertices (steps)
    graph_with_vertices =
      Enum.reduce(plan_instructions, graph, fn plan_instruction, acc_graph ->
        Graph.add_vertex(acc_graph, plan_instruction.name)
      end)

    # Add edges for dependencies
    graph_with_edges =
      Enum.reduce(plan_instructions, graph_with_vertices, fn plan_instruction, acc_graph ->
        Enum.reduce(plan_instruction.depends_on, acc_graph, fn dep, edge_graph ->
          Graph.add_edge(edge_graph, dep, plan_instruction.name)
        end)
      end)

    {:ok, graph_with_edges}
  end

  defp validate_graph(graph) do
    if Graph.is_acyclic?(graph) do
      :ok
    else
      case find_cycle(graph) do
        nil ->
          {:error, Error.validation_error("Plan contains circular dependencies", %{})}

        cycle ->
          {:error,
           Error.validation_error("Plan contains circular dependencies", %{
             cycle: cycle
           })}
      end
    end
  end

  # Simple cycle detection using DFS
  # Dialyzer complains about MapSet opaque type but these are false positives
  @dialyzer {:nowarn_function, find_cycle: 1, find_cycle_dfs: 4, dfs_visit: 5, dfs_neighbors: 5}

  @spec find_cycle(Graph.t()) :: [atom()] | nil
  defp find_cycle(graph) do
    vertices = Graph.vertices(graph)
    find_cycle_dfs(graph, vertices, MapSet.new(), MapSet.new())
  end

  @spec find_cycle_dfs(Graph.t(), [atom()], MapSet.t(), MapSet.t()) :: [atom()] | nil
  defp find_cycle_dfs(_graph, [], _visited, _rec_stack), do: nil

  defp find_cycle_dfs(graph, [vertex | rest], visited, rec_stack) do
    if MapSet.member?(visited, vertex) do
      find_cycle_dfs(graph, rest, visited, rec_stack)
    else
      case dfs_visit(graph, vertex, visited, rec_stack, []) do
        {:cycle, path} -> path
        {:ok, new_visited} -> find_cycle_dfs(graph, rest, new_visited, rec_stack)
      end
    end
  end

  @spec dfs_visit(Graph.t(), atom(), MapSet.t(), MapSet.t(), [atom()]) ::
          {:cycle, [atom()]} | {:ok, MapSet.t()}
  defp dfs_visit(graph, vertex, visited, rec_stack, path) do
    if MapSet.member?(rec_stack, vertex) do
      {:cycle, Enum.reverse([vertex | path])}
    else
      visited = MapSet.put(visited, vertex)
      rec_stack = MapSet.put(rec_stack, vertex)
      neighbors = Graph.out_neighbors(graph, vertex)

      case dfs_neighbors(graph, neighbors, visited, rec_stack, [vertex | path]) do
        {:cycle, cycle_path} -> {:cycle, cycle_path}
        {:ok, final_visited} -> {:ok, final_visited}
      end
    end
  end

  @spec dfs_neighbors(Graph.t(), [atom()], MapSet.t(), MapSet.t(), [atom()]) ::
          {:cycle, [atom()]} | {:ok, MapSet.t()}
  defp dfs_neighbors(_graph, [], visited, _rec_stack, _path), do: {:ok, visited}

  defp dfs_neighbors(graph, [neighbor | rest], visited, rec_stack, path) do
    case dfs_visit(graph, neighbor, visited, rec_stack, path) do
      {:cycle, cycle_path} -> {:cycle, cycle_path}
      {:ok, new_visited} -> dfs_neighbors(graph, rest, new_visited, rec_stack, path)
    end
  end

  defp build_execution_phases(sorted_vertices, graph) do
    # Group vertices by their depth in the dependency tree
    vertex_depths =
      Enum.reduce(sorted_vertices, %{}, fn vertex, acc ->
        depth = calculate_depth(vertex, graph, acc)
        Map.put(acc, vertex, depth)
      end)

    # Group by depth to create phases
    vertex_depths
    |> Enum.group_by(fn {_vertex, depth} -> depth end, fn {vertex, _depth} -> vertex end)
    |> Enum.sort_by(fn {depth, _vertices} -> depth end)
    |> Enum.map(fn {_depth, vertices} -> vertices end)
  end

  defp calculate_depth(vertex, graph, known_depths) do
    predecessors = Graph.in_neighbors(graph, vertex)

    if Enum.empty?(predecessors) do
      0
    else
      max_pred_depth =
        predecessors
        |> Enum.map(fn pred -> Map.get(known_depths, pred, 0) end)
        |> Enum.max()

      max_pred_depth + 1
    end
  end

  defp instruction_to_step_def(%Instruction{action: action, params: params, opts: opts}) do
    # Remove common opts that aren't part of the step definition
    clean_opts = Keyword.delete(opts, :opts)

    case {params, clean_opts} do
      {params, []} when map_size(params) == 0 -> action
      {params, []} -> {action, params}
      {params, opts} when map_size(params) == 0 and opts != [] -> {action, opts}
      {params, opts} when opts != [] -> {action, params, opts}
    end
  end

  defp add_depends_on_to_step_def(step_def, depends_on) do
    case step_def do
      action when is_atom(action) ->
        {action, depends_on: depends_on}

      {action, params} when is_map(params) ->
        {action, params, depends_on: depends_on}

      {action, opts} when is_list(opts) ->
        {action, Keyword.put(opts, :depends_on, depends_on)}

      {action, params, opts} ->
        {action, params, Keyword.put(opts, :depends_on, depends_on)}
    end
  end
end
