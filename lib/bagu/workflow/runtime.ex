defmodule Bagu.Workflow.Runtime do
  @moduledoc false

  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.Runic.Directive.ExecuteRunnable
  alias Jido.Runic.{ActionNode, Introspection, Strategy}
  alias Runic.Workflow
  alias Runic.Workflow.Invokable

  @definition_key :__bagu_workflow_definition__
  @step_key :__bagu_workflow_step__
  @state_key :__bagu_workflow_state__

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
  def state_key, do: @state_key

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
      with {:ok, runtime_opts} <- normalize_opts(opts),
           {:ok, parsed_input} <- parse_input(definition, input),
           :ok <- validate_runtime_refs(definition, runtime_opts) do
        state = initial_state(definition, parsed_input, runtime_opts)
        run_strategy(definition, state, runtime_opts)
      end

    case result do
      {:error, reason} ->
        {:error, Bagu.Error.Normalize.workflow_error(reason, workflow_id: definition.id)}

      other ->
        other
    end
  end

  @doc false
  @spec run_step(map(), map()) :: {:ok, map()} | {:error, term()}
  def run_step(params, _context) when is_map(params) do
    definition = Map.fetch!(params, @definition_key)
    step = Map.fetch!(params, @step_key)
    state = extract_state!(params)

    case execute_step(definition, step, state) do
      {:ok, result} ->
        updated_state = put_in(state, [:steps, step.name], result)
        {:ok, %{@state_key => updated_state}}

      {:error, reason} ->
        {:error, step_error(definition, step, reason)}
    end
  end

  defp action_node(definition, step) do
    ActionNode.new(
      Bagu.Workflow.StepAction,
      %{
        @definition_key => definition,
        @step_key => step
      },
      name: step.name,
      inputs: [{@state_key, [type: :any, doc: "Bagu workflow runtime state"]}],
      outputs: [{@state_key, [type: :any, doc: "Bagu workflow runtime state"]}],
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

  defp normalize_opts(opts) do
    with {:ok, context} <- Bagu.Context.normalize(Keyword.get(opts, :context, %{})),
         {:ok, agents} <- normalize_agents(Keyword.get(opts, :agents, %{})),
         {:ok, timeout} <- normalize_timeout(Keyword.get(opts, :timeout, 30_000)),
         {:ok, return} <- normalize_return(Keyword.get(opts, :return, :output)) do
      {:ok, %{context: context, agents: agents, timeout: timeout, return: return}}
    end
  end

  defp normalize_agents(agents) when is_map(agents), do: {:ok, agents}

  defp normalize_agents(agents) when is_list(agents) do
    if Keyword.keyword?(agents) do
      {:ok, Map.new(agents)}
    else
      {:error, Bagu.Error.validation_error("Invalid workflow agents: pass `agents:` as a map or keyword list.")}
    end
  end

  defp normalize_agents(other) do
    {:error,
     Bagu.Error.validation_error("Invalid workflow agents: pass `agents:` as a map or keyword list.",
       field: :agents,
       value: other,
       details: %{reason: :expected_map}
     )}
  end

  defp normalize_timeout(timeout) when is_integer(timeout) and timeout > 0, do: {:ok, timeout}

  defp normalize_timeout(other) do
    {:error,
     Bagu.Error.validation_error("Invalid workflow timeout: expected a positive integer.",
       field: :timeout,
       value: other,
       details: %{reason: :invalid_timeout}
     )}
  end

  defp normalize_return(return) when return in [:output, :debug], do: {:ok, return}

  defp normalize_return(other) do
    {:error,
     Bagu.Error.validation_error("Invalid workflow return option: expected `:output` or `:debug`.",
       field: :return,
       value: other,
       details: %{reason: :invalid_return}
     )}
  end

  defp parse_input(definition, input) do
    with {:ok, input_map} <- coerce_input_map(input),
         {:ok, parsed} <- do_parse_input(definition, input_map) do
      {:ok, parsed}
    end
  end

  defp coerce_input_map(input) do
    case Bagu.Context.coerce_map(input) do
      {:ok, map} ->
        {:ok, map}

      :error ->
        {:error,
         Bagu.Error.validation_error("Invalid workflow input: pass input as a map or keyword list.",
           field: :input,
           value: input,
           details: %{reason: :expected_map}
         )}
    end
  end

  defp do_parse_input(definition, input_map) do
    case Zoi.parse(definition.input_schema, input_map) do
      {:ok, parsed} when is_map(parsed) ->
        {:ok, parsed}

      {:ok, other} ->
        {:error,
         Bagu.Error.config_error("Workflow input schema must parse to a map.",
           field: :input_schema,
           value: other,
           details: %{workflow_id: definition.id, reason: :expected_map_result}
         )}

      {:error, errors} ->
        {:error,
         Bagu.Error.validation_error("Invalid workflow input:\n" <> Zoi.prettify_errors(errors),
           field: :input,
           value: input_map,
           details: %{workflow_id: definition.id, reason: :schema, errors: Zoi.treefy_errors(errors)}
         )}
    end
  end

  defp validate_runtime_refs(definition, %{context: context, agents: agents}) do
    with :ok <- validate_context_refs(definition, context),
         :ok <- validate_imported_agent_refs(definition, agents) do
      :ok
    end
  end

  defp validate_context_refs(definition, context) do
    Enum.reduce_while(definition.context_refs, :ok, fn key, :ok ->
      if has_equivalent_key?(context, key) do
        {:cont, :ok}
      else
        {:halt,
         {:error,
          Bagu.Error.validation_error("Missing workflow context key `#{key}`.",
            field: :context,
            value: context,
            details: %{workflow_id: definition.id, reason: :missing_context, key: key}
          )}}
      end
    end)
  end

  defp validate_imported_agent_refs(definition, agents) do
    Enum.reduce_while(definition.imported_agent_refs, :ok, fn key, :ok ->
      if has_equivalent_key?(agents, key) do
        {:cont, :ok}
      else
        {:halt,
         {:error,
          Bagu.Error.validation_error("Missing imported workflow agent `#{key}`.",
            field: :agents,
            value: agents,
            details: %{workflow_id: definition.id, reason: :missing_imported_agent, key: key}
          )}}
      end
    end)
  end

  defp initial_state(definition, parsed_input, runtime_opts) do
    %{
      input: parsed_input,
      context: runtime_opts.context,
      agents: runtime_opts.agents,
      steps: %{},
      workflow_id: definition.id,
      timeout: runtime_opts.timeout
    }
  end

  defp run_strategy(definition, state, runtime_opts) do
    workflow = build_workflow(definition)

    agent = %Jido.Agent{
      id: "bagu-workflow-#{definition.id}-#{System.unique_integer([:positive])}",
      name: definition.id,
      description: definition.description || "Bagu workflow #{definition.id}",
      schema: [],
      state: %{}
    }

    strategy_context = %{agent_module: Bagu.Workflow.StepAction, strategy_opts: [workflow: workflow]}
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
    Strategy.cmd(agent, [instruction], %{agent_module: Bagu.Workflow.StepAction, strategy_opts: []})
  end

  defp apply_result(agent, runnable) do
    instruction = %Jido.Instruction{action: :runic_apply_result, params: %{runnable: runnable}}
    Strategy.cmd(agent, [instruction], %{agent_module: Bagu.Workflow.StepAction, strategy_opts: []})
  end

  defp drain_strategy(definition, agent, directives, deadline),
    do: drain_strategy(definition, agent, directives, deadline, [])

  defp drain_strategy(_definition, agent, [], _deadline, emitted), do: {:ok, agent, Enum.reverse(emitted)}

  defp drain_strategy(definition, agent, [%ExecuteRunnable{} = directive | rest], deadline, emitted) do
    if System.monotonic_time(:millisecond) > deadline do
      {:error,
       Bagu.Error.execution_error("Workflow execution timed out.",
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
           Bagu.Error.execution_error("Workflow runnable did not complete.",
             phase: :workflow,
             details: %{workflow_id: definition.id, status: other, runnable_id: runnable.id, cause: other}
           )}
      end
    end
  end

  defp drain_strategy(definition, agent, [directive | rest], deadline, emitted) do
    if System.monotonic_time(:millisecond) > deadline do
      {:error,
       Bagu.Error.execution_error("Workflow execution timed out.",
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
        final_state = select_final_state(definition, productions)

        with {:ok, output} <- resolve_value(definition.output, final_state) do
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
         Bagu.Error.execution_error("Workflow execution did not produce output.",
           phase: :workflow,
           details: %{workflow_id: definition.id, status: status, cause: status}
         )}
    end
  end

  defp execute_step(_definition, %{kind: :tool} = step, state) do
    with {:ok, params} <- resolve_value(step.input, state),
         {:ok, params} <- ensure_map(params, :tool_input) do
      Jido.Exec.run(step.target, params, state.context,
        timeout: state.timeout,
        log_level: :warning,
        max_retries: 0
      )
      |> normalize_step_result()
    end
  end

  defp execute_step(_definition, %{kind: :function, target: {module, function, 2}} = step, state) do
    with {:ok, params} <- resolve_value(step.input, state),
         {:ok, params} <- ensure_map(params, :function_input) do
      try do
        module
        |> apply(function, [params, state.context])
        |> normalize_function_result()
      rescue
        error -> {:error, error}
      catch
        kind, reason -> {:error, {kind, reason}}
      end
    end
  end

  defp execute_step(_definition, %{kind: :agent} = step, state) do
    with {:ok, prompt} <- resolve_value(step.prompt, state),
         {:ok, prompt} <- ensure_prompt(prompt),
         {:ok, context} <- resolve_value(step.context, state),
         {:ok, context} <- ensure_map(context, :agent_context),
         {:ok, target} <- resolve_agent_target(step.target, state) do
      run_agent_target(target, prompt, context, state.timeout)
    end
  end

  defp normalize_step_result({:ok, result}), do: {:ok, result}
  defp normalize_step_result({:ok, result, _extra}), do: {:ok, result}
  defp normalize_step_result({:error, reason}), do: {:error, visible_reason(reason)}
  defp normalize_step_result(other), do: {:error, {:invalid_step_result, other}}

  defp normalize_function_result({:ok, result}), do: {:ok, result}
  defp normalize_function_result({:error, reason}), do: {:error, visible_reason(reason)}
  defp normalize_function_result(result), do: {:ok, result}

  defp resolve_agent_target({:imported, key}, state) do
    case fetch_equivalent(state.agents, key) do
      {:ok, target} -> {:ok, target}
      :error -> {:error, {:missing_imported_agent, key}}
    end
  end

  defp resolve_agent_target(target, _state), do: {:ok, target}

  defp run_agent_target(pid, prompt, context, timeout) when is_pid(pid) do
    call_agent(fn -> Bagu.chat(pid, prompt, context: context, timeout: timeout) end, timeout)
  end

  defp run_agent_target(%Bagu.ImportedAgent{} = agent, prompt, context, timeout) do
    run_started_agent(fn opts -> Bagu.start_agent(agent, opts) end, fn pid ->
      call_agent(fn -> Bagu.chat(pid, prompt, context: context, timeout: timeout) end, timeout)
    end)
  end

  defp run_agent_target(module, prompt, context, timeout) when is_atom(module) do
    run_started_agent(fn opts -> module.start_link(opts) end, fn pid ->
      call_agent(fn -> module.chat(pid, prompt, context: context, timeout: timeout) end, timeout)
    end)
  end

  defp run_agent_target(other, _prompt, _context, _timeout), do: {:error, {:invalid_agent_target, other}}

  defp run_started_agent(start_fun, call_fun) do
    child_id = "bagu-workflow-agent-#{System.unique_integer([:positive])}"

    case normalize_start_result(start_fun.(id: child_id)) do
      {:ok, pid} ->
        try do
          call_fun.(pid)
        after
          _ = Bagu.stop_agent(pid)
        end

      {:error, reason} ->
        {:error, {:start_failed, reason}}
    end
  rescue
    error -> {:error, error}
  catch
    :exit, reason -> {:error, reason}
  end

  defp normalize_start_result({:ok, pid}) when is_pid(pid), do: {:ok, pid}
  defp normalize_start_result({:ok, pid, _info}) when is_pid(pid), do: {:ok, pid}
  defp normalize_start_result({:error, reason}), do: {:error, reason}
  defp normalize_start_result(:ignore), do: {:error, :ignore}
  defp normalize_start_result(other), do: {:error, {:invalid_start_return, other}}

  defp call_agent(fun, timeout) do
    task = Task.async(fun)

    case Task.yield(task, timeout) do
      {:ok, {:ok, result}} ->
        {:ok, result}

      {:ok, {:error, reason}} ->
        {:error, reason}

      {:ok, {:interrupt, interrupt}} ->
        {:error, {:interrupt, interrupt}}

      {:ok, other} ->
        {:error, {:invalid_agent_result, other}}

      {:exit, reason} ->
        {:error, reason}

      nil ->
        Task.shutdown(task, :brutal_kill)
        {:error, {:timeout, timeout}}
    end
  end

  defp ensure_map(value, _field) when is_map(value), do: {:ok, value}

  defp ensure_map(value, field) do
    {:error, {:expected_map, field, value}}
  end

  defp ensure_prompt(prompt) when is_binary(prompt), do: {:ok, prompt}
  defp ensure_prompt(prompt), do: {:error, {:expected_prompt, prompt}}

  defp extract_state!(%{@state_key => state}) when is_map(state), do: state

  defp extract_state!(%{input: input}) when is_list(input) do
    input
    |> Enum.map(&extract_state_from_fact!/1)
    |> merge_states()
  end

  defp extract_state!(%{input: input}) do
    extract_state_from_fact!(input)
  end

  defp extract_state_from_fact!(%{@state_key => state}) when is_map(state), do: state
  defp extract_state_from_fact!(state) when is_map(state) and is_map_key(state, :steps), do: state

  defp extract_state_from_fact!(facts) when is_list(facts),
    do: facts |> Enum.map(&extract_state_from_fact!/1) |> merge_states()

  defp extract_state_from_fact!(other) do
    raise ArgumentError, "expected Bagu workflow state fact, got: #{inspect(other)}"
  end

  defp merge_states([state]), do: state

  defp merge_states([first | rest]) do
    Enum.reduce(rest, first, fn state, acc ->
      %{acc | steps: Map.merge(acc.steps, state.steps)}
    end)
  end

  defp merge_states([]), do: raise(ArgumentError, "expected at least one Bagu workflow state")

  defp select_final_state(definition, productions) do
    states = Enum.map(productions, &extract_state_from_fact!/1)

    states
    |> Enum.reverse()
    |> Enum.find(fn state -> match?({:ok, _}, resolve_value(definition.output, state)) end)
    |> case do
      nil -> Enum.max_by(states, &map_size(&1.steps))
      state -> state
    end
  end

  defp resolve_value({:bagu_workflow_ref, :input, key}, state), do: fetch_ref(state.input, key, :input)
  defp resolve_value({:bagu_workflow_ref, :context, key}, state), do: fetch_ref(state.context, key, :context)
  defp resolve_value({:bagu_workflow_ref, :value, value}, _state), do: {:ok, value}

  defp resolve_value({:bagu_workflow_ref, :from, step, nil}, state), do: fetch_ref(state.steps, step, :step)

  defp resolve_value({:bagu_workflow_ref, :from, step, path}, state) when is_list(path) do
    with {:ok, value} <- fetch_ref(state.steps, step, :step) do
      resolve_path(value, path)
    end
  end

  defp resolve_value(%{} = map, state) do
    Enum.reduce_while(map, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      case resolve_value(value, state) do
        {:ok, resolved} -> {:cont, {:ok, Map.put(acc, key, resolved)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp resolve_value(list, state) when is_list(list) do
    list
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, acc} ->
      case resolve_value(value, state) do
        {:ok, resolved} -> {:cont, {:ok, [resolved | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end

  defp resolve_value(tuple, state) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> resolve_value(state)
    |> case do
      {:ok, values} -> {:ok, List.to_tuple(values)}
      error -> error
    end
  end

  defp resolve_value(value, _state), do: {:ok, value}

  defp resolve_path(value, []), do: {:ok, value}

  defp resolve_path(value, [key | rest]) when is_map(value) do
    with {:ok, nested} <- fetch_ref(value, key, :field) do
      resolve_path(nested, rest)
    end
  end

  defp resolve_path(value, path), do: {:error, {:missing_field, path, value}}

  defp fetch_ref(map, key, kind) when is_map(map) do
    case fetch_equivalent(map, key) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, {:missing_ref, kind, key}}
    end
  end

  defp fetch_equivalent(map, key) when is_map(map) do
    cond do
      Map.has_key?(map, key) ->
        {:ok, Map.fetch!(map, key)}

      is_atom(key) and Map.has_key?(map, Atom.to_string(key)) ->
        {:ok, Map.fetch!(map, Atom.to_string(key))}

      is_binary(key) ->
        case Enum.find(Map.keys(map), &(is_atom(&1) and Atom.to_string(&1) == key)) do
          nil -> :error
          existing -> {:ok, Map.fetch!(map, existing)}
        end

      true ->
        :error
    end
  end

  defp has_equivalent_key?(map, key) when is_map(map), do: match?({:ok, _}, fetch_equivalent(map, key))

  defp step_error(definition, step, reason) do
    Bagu.Error.execution_error("Workflow #{definition.id} step #{step.name} failed.",
      phase: :workflow_step,
      details: %{
        workflow_id: definition.id,
        step: step.name,
        kind: step.kind,
        target: step.target,
        reason: reason,
        cause: reason
      }
    )
  end

  defp visible_reason(%{message: message}) when is_binary(message), do: message
  defp visible_reason(reason), do: reason
end
