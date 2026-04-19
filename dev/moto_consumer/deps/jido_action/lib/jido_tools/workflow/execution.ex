defmodule Jido.Tools.Workflow.Execution do
  @moduledoc false

  alias Jido.Action.Error
  alias Jido.Exec
  alias Jido.Exec.Supervisors
  alias Jido.Instruction

  @deadline_key :__jido_deadline_ms__

  @spec execute_workflow(list(), map(), map(), module()) :: {:ok, map()} | {:error, Exception.t()}
  def execute_workflow(steps, params, context, module) do
    initial_acc = {:ok, params, %{}}

    steps
    |> Enum.reduce_while(initial_acc, &reduce_step(&1, &2, context, module))
    |> case do
      {:ok, _final_params, final_results} -> {:ok, final_results}
      {:error, reason} -> {:error, reason}
    end
  end

  defp reduce_step(step, {_status, current_params, results}, context, module) do
    case module.execute_step(step, current_params, context) do
      {:ok, step_result} when is_map(step_result) ->
        updated_results = Map.merge(results, step_result)
        updated_params = Map.merge(current_params, step_result)
        {:cont, {:ok, updated_params, updated_results}}

      {:ok, step_result} ->
        {:halt,
         {:error,
          Error.execution_error("Expected workflow step result to be a map", %{
            type: :invalid_step_result,
            reason: step_result
          })}}

      {:error, reason} ->
        {:halt, {:error, reason}}
    end
  end

  @doc false
  @spec execute_step(tuple(), map(), map(), module()) :: {:ok, any()} | {:error, Exception.t()}
  def execute_step(step, params, context, module) do
    case step do
      {:step, _metadata, [instruction]} ->
        execute_instruction(instruction, params, context)

      {:branch, metadata, [condition, true_branch, false_branch]} ->
        execute_branch(condition, true_branch, false_branch, params, context, metadata, module)

      {:converge, _metadata, [instruction]} ->
        execute_instruction(instruction, params, context)

      {:parallel, metadata, instructions} ->
        execute_parallel(instructions, params, context, metadata, module)

      _ ->
        {:error,
         Error.execution_error("Unknown workflow step type", %{
           type: :invalid_step,
           reason: step
         })}
    end
  end

  defp execute_instruction(instruction, params, context) do
    case Instruction.normalize_single(instruction) do
      {:ok, %Instruction{} = normalized} ->
        run_normalized_instruction(normalized, params, context)

      {:error, reason} ->
        {:error,
         Error.execution_error("Failed to normalize workflow instruction", %{
           type: :invalid_instruction,
           reason: reason,
           instruction: instruction
         })}
    end
  end

  defp run_normalized_instruction(%Instruction{} = normalized, params, context) do
    merged_params = Map.merge(params, normalized.params)
    merged_context = Map.merge(normalized.context, context)
    execution_opts = default_internal_retry_opts(normalized.opts)

    instruction = %{
      normalized
      | params: merged_params,
        context: merged_context,
        opts: execution_opts
    }

    case Exec.run(instruction) do
      {:ok, result} ->
        {:ok, result}

      {:ok, result, _other} ->
        {:ok, result}

      {:error, reason} ->
        {:error, reason}

      {:error, reason, _other} ->
        {:error, reason}
    end
  end

  defp default_internal_retry_opts(opts) do
    Keyword.put_new(opts, :max_retries, 0)
  end

  defp execute_branch(condition, true_branch, false_branch, params, context, _metadata, module)
       when is_boolean(condition) do
    if condition do
      module.execute_step(true_branch, params, context)
    else
      module.execute_step(false_branch, params, context)
    end
  end

  defp execute_branch(
         condition,
         _true_branch,
         _false_branch,
         _params,
         _context,
         metadata,
         _module
       ) do
    {:error,
     Error.execution_error("Invalid or unhandled condition in workflow branch", %{
       type: :invalid_condition,
       reason: condition,
       metadata: metadata
     })}
  end

  defp execute_parallel(instructions, params, context, metadata, module) do
    max_concurrency = Keyword.get(metadata, :max_concurrency, System.schedulers_online())
    timeout = Keyword.get(metadata, :timeout_ms, :infinity)
    fail_on_error = Keyword.get(metadata, :fail_on_error, false)

    # Extract jido instance from context if present (set by parent workflow)
    jido_opts = if context[:__jido__], do: [jido: context[:__jido__]], else: []

    # Resolve supervisor based on jido: option (defaults to global)
    task_sup = Supervisors.task_supervisor(jido_opts)

    with {:ok, effective_timeout} <- resolve_parallel_timeout(timeout, context) do
      stream_opts = [
        ordered: true,
        max_concurrency: max_concurrency,
        timeout: effective_timeout,
        on_timeout: :kill_task
      ]

      results =
        Task.Supervisor.async_stream(
          task_sup,
          instructions,
          fn instruction ->
            execute_parallel_instruction(instruction, params, context, module)
          end,
          stream_opts
        )
        |> Enum.map(&handle_stream_result/1)

      finalize_parallel_result(results, fail_on_error)
    end
  end

  defp handle_stream_result({:ok, %{error: reason}}), do: {:error, reason}
  defp handle_stream_result({:ok, value}), do: {:ok, value}

  defp handle_stream_result({:exit, :timeout}) do
    {:error, Error.timeout_error("Parallel task timed out", %{})}
  end

  defp handle_stream_result({:exit, reason}) do
    {:error, Error.execution_error("Parallel task exited", %{reason: reason})}
  end

  defp finalize_parallel_result(results, false) do
    {:ok, %{parallel_results: Enum.map(results, &normalize_parallel_result/1)}}
  end

  defp finalize_parallel_result(results, true) do
    case Enum.find(results, &match?({:error, _}, &1)) do
      nil ->
        {:ok, %{parallel_results: Enum.map(results, &normalize_parallel_result/1)}}

      {:error, reason} ->
        {:error,
         Error.execution_error("Parallel workflow step failed", %{
           reason: reason
         })}
    end
  end

  defp normalize_parallel_result({:ok, value}), do: value
  defp normalize_parallel_result({:error, reason}), do: %{error: reason}
  defp normalize_parallel_result(other), do: other

  defp resolve_parallel_timeout(timeout, context) do
    case Map.get(context, @deadline_key) do
      deadline_ms when is_integer(deadline_ms) ->
        now = System.monotonic_time(:millisecond)
        remaining = deadline_ms - now

        if remaining <= 0 do
          {:error,
           Error.timeout_error("Execution deadline exceeded before parallel step dispatch", %{
             deadline_ms: deadline_ms,
             now_ms: now
           })}
        else
          {:ok, cap_timeout(timeout, remaining)}
        end

      _ ->
        {:ok, timeout}
    end
  end

  defp cap_timeout(:infinity, remaining), do: remaining

  defp cap_timeout(timeout, remaining) when is_integer(timeout) and timeout >= 0,
    do: min(timeout, remaining)

  defp cap_timeout(timeout, _remaining), do: timeout

  defp execute_parallel_instruction(instruction, params, context, module) do
    case module.execute_step(instruction, params, context) do
      {:ok, result} -> result
      {:error, reason} -> %{error: reason}
    end
  rescue
    e ->
      %{error: Error.execution_error("Parallel step raised", %{exception: e})}
  catch
    kind, reason ->
      %{error: Error.execution_error("Parallel step caught", %{kind: kind, reason: reason})}
  end
end
