defmodule Jido.Exec.Async do
  @moduledoc """
  Handles asynchronous execution of Actions using Task.Supervisor.

  This module provides the core async implementation for Jido.Exec, 
  managing task supervision, cleanup, and async lifecycle.
  """
  use Private

  alias Jido.Action.Error
  alias Jido.Exec.Supervisors

  require Logger

  @default_timeout 5000
  @cancel_wait_ms 100
  @async_owner_key :jido_async_owner

  # Helper functions to get configuration values with fallbacks
  defp get_default_timeout,
    do: resolve_non_neg_integer_config(:default_timeout, @default_timeout)

  defp resolve_non_neg_integer_config(key, fallback) do
    case Application.get_env(:jido_action, key, fallback) do
      value when is_integer(value) and value >= 0 ->
        value

      invalid ->
        Logger.warning(
          "Invalid :jido_action config for #{inspect(key)}: #{inspect(invalid)}. " <>
            "Expected a non-negative integer; using fallback #{fallback}."
        )

        fallback
    end
  end

  @type action :: module()
  @type params :: map()
  @type context :: map()
  @type run_opts :: [timeout: non_neg_integer(), jido: atom()]
  @type async_ref :: %{
          required(:ref) => reference(),
          required(:pid) => pid(),
          optional(:owner) => pid(),
          optional(:monitor_ref) => reference()
        }

  # Execution result types
  @type exec_success :: {:ok, map()}
  @type exec_success_dir :: {:ok, map(), any()}
  @type exec_error :: {:error, Exception.t()}
  @type exec_error_dir :: {:error, Exception.t(), any()}

  @type exec_result ::
          exec_success
          | exec_success_dir
          | exec_error
          | exec_error_dir

  @doc """
  Starts an asynchronous Action execution.

  This function creates a supervised task that calls back to Jido.Exec.run/4 
  to ensure feature consistency across sync and async execution paths.

  ## Parameters

  - `action`: The module implementing the Action behavior.
  - `params`: A map of input parameters for the Action.
  - `context`: A map providing additional context for the Action execution.
  - `opts`: Options controlling the execution (same as Jido.Exec.run/4).
    - `:jido` - Optional instance name for isolation. Routes execution through instance-scoped supervisors.

  ## Returns

  An `async_ref` map containing:
  - `:ref` - A unique reference for this async action.
  - `:pid` - The PID of the process executing the Action.
  - `:monitor_ref` - Monitor reference used for deterministic cleanup.
  """
  @spec start(action(), params(), context(), run_opts()) :: async_ref()
  def start(action, params \\ %{}, context \\ %{}, opts \\ []) do
    ref = make_ref()
    owner = self()

    # Resolve supervisor based on jido: option (defaults to global)
    task_sup = Supervisors.task_supervisor(opts)

    # Start the task under the resolved TaskSupervisor.
    # If the supervisor is not running, this will raise an error.
    {:ok, pid} =
      Task.Supervisor.start_child(task_sup, fn ->
        Process.put(@async_owner_key, owner)
        result = Jido.Exec.run(action, params, context, opts)
        send(owner, {:action_async_result, ref, result})
        result
      end)

    # Persist monitor_ref in async_ref so await can demonitor/flush deterministically.
    monitor_ref = Process.monitor(pid)

    %{ref: ref, pid: pid, owner: owner, monitor_ref: monitor_ref}
  end

  @doc """
  Waits for the result of an asynchronous Action execution.

  ## Parameters

  - `async_ref`: The reference returned by `start/4`.
  - `timeout`: Maximum time (in ms) to wait for the result (default: 5000).

  ## Returns

  - `{:ok, result}` if the Action executes successfully.
  - `{:error, reason}` if an error occurs during execution or if the action times out.
  """
  @spec await(async_ref()) :: exec_result
  def await(async_ref), do: await(async_ref, get_default_timeout())

  @doc """
  Awaits the completion of an asynchronous Action with a custom timeout.

  ## Parameters

  - `async_ref`: The async reference returned by `start/4`.
  - `timeout`: Maximum time to wait in milliseconds.

  ## Returns

  - `{:ok, result}` if the Action completes successfully.
  - `{:error, reason}` if an error occurs or timeout is reached.
  """
  @spec await(async_ref(), timeout()) :: exec_result
  def await(%{ref: ref, pid: pid} = async_ref, timeout) do
    with :ok <- validate_owner(async_ref, :await) do
      monitor_ref = Map.get_lazy(async_ref, :monitor_ref, fn -> Process.monitor(pid) end)

      result = await_result(ref, pid, monitor_ref, timeout)
      cleanup_after_await(ref, monitor_ref)
      result
    end
  end

  defp await_result(ref, pid, monitor_ref, timeout) do
    receive do
      {:action_async_result, ^ref, result} ->
        result

      {:DOWN, ^monitor_ref, :process, ^pid, :normal} ->
        # Process completed normally, but result message may still be in-flight.
        receive do
          {:action_async_result, ^ref, result} -> result
        after
          100 ->
            {:error, Error.execution_error("Process completed but result was not received")}
        end

      {:DOWN, ^monitor_ref, :process, ^pid, reason} ->
        {:error, Error.execution_error("Server error in async action: #{inspect(reason)}")}
    after
      timeout ->
        Process.exit(pid, :kill)
        wait_for_down(monitor_ref, pid, 100)

        {:error,
         Error.timeout_error("Async action timed out after #{timeout}ms", %{timeout: timeout})}
    end
  end

  defp wait_for_down(monitor_ref, pid, wait_ms) do
    receive do
      {:DOWN, ^monitor_ref, :process, ^pid, _} -> :ok
    after
      wait_ms -> :ok
    end
  end

  defp cleanup_after_await(ref, monitor_ref) do
    Process.demonitor(monitor_ref, [:flush])
    flush_result_messages(ref)
  end

  defp flush_result_messages(ref) do
    receive do
      {:action_async_result, ^ref, _} ->
        flush_result_messages(ref)
    after
      0 ->
        :ok
    end
  end

  @doc """
  Cancels a running asynchronous Action execution.

  ## Parameters

  - `async_ref`: The reference returned by `start/4`, or just the PID of the process to cancel.

  ## Returns

  - `:ok` if the cancellation was successful.
  - `{:error, reason}` if the cancellation failed or the input was invalid.
  """
  @spec cancel(async_ref() | pid()) :: :ok | exec_error
  def cancel(%{ref: ref, pid: pid} = async_ref) do
    with :ok <- validate_owner(async_ref, :cancel) do
      monitor_ref = get_cancel_monitor_ref(async_ref, pid)
      cancel_with_cleanup(ref, pid, monitor_ref)
    end
  end

  def cancel(%{pid: pid} = async_ref) do
    with :ok <- validate_owner(async_ref, :cancel) do
      cancel(pid)
    end
  end

  def cancel(pid) when is_pid(pid) do
    with :ok <- validate_pid_owner(pid, :cancel) do
      monitor_ref = Process.monitor(pid)
      cancel_with_cleanup(nil, pid, monitor_ref)
    end
  end

  def cancel(_), do: {:error, Error.validation_error("Invalid async ref for cancellation")}

  defp get_cancel_monitor_ref(%{monitor_ref: monitor_ref}, _pid) when is_reference(monitor_ref),
    do: monitor_ref

  defp get_cancel_monitor_ref(_async_ref, pid), do: Process.monitor(pid)

  defp cancel_with_cleanup(ref, pid, monitor_ref) do
    Process.exit(pid, :shutdown)
    wait_for_down(monitor_ref, pid, @cancel_wait_ms)
    Process.demonitor(monitor_ref, [:flush])
    flush_down_messages(pid)

    if is_reference(ref), do: flush_result_messages(ref)
    :ok
  end

  defp flush_down_messages(pid) do
    receive do
      {:DOWN, _monitor_ref, :process, ^pid, _reason} ->
        flush_down_messages(pid)
    after
      0 ->
        :ok
    end
  end

  defp validate_owner(%{owner: owner}, operation) when is_pid(owner) do
    validate_owner_pid(owner, operation)
  end

  defp validate_owner(_async_ref, _operation), do: :ok

  defp validate_pid_owner(pid, operation) do
    case get_pid_owner(pid) do
      {:ok, owner} -> validate_owner_pid(owner, operation)
      :unknown -> :ok
    end
  end

  defp get_pid_owner(pid) do
    case Process.info(pid, :dictionary) do
      {:dictionary, dictionary} ->
        case List.keyfind(dictionary, @async_owner_key, 0) do
          {@async_owner_key, owner} when is_pid(owner) -> {:ok, owner}
          _ -> :unknown
        end

      _ ->
        :unknown
    end
  end

  defp validate_owner_pid(owner, operation) do
    caller = self()

    if caller == owner do
      :ok
    else
      {:error,
       Error.validation_error(
         "Only the owner process can #{operation} this async action",
         %{
           operation: operation,
           owner: owner,
           caller: caller
         }
       )}
    end
  end
end
