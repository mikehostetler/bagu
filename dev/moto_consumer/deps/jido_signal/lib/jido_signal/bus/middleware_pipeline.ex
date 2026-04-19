defmodule Jido.Signal.Bus.MiddlewarePipeline do
  @moduledoc """
  Handles execution of middleware chains for signal bus operations.

  This module provides functions to execute middleware callbacks in sequence,
  allowing each middleware to transform signals or control the flow of execution.
  Middleware state changes are propagated back to the caller for persistence.

  ## Timeout Protection

  All middleware callbacks are executed with a configurable timeout (default: 100ms)
  to prevent slow middleware from blocking the Bus GenServer indefinitely. If a
  middleware callback exceeds the timeout, the operation fails with `:middleware_timeout`.
  """

  alias Jido.Signal
  alias Jido.Signal.Bus.Middleware
  alias Jido.Signal.Bus.Subscriber
  alias Jido.Signal.Error
  alias Jido.Signal.Telemetry

  @type middleware_config :: {module(), term()}
  @type context :: Middleware.context()

  @default_timeout_ms 100

  @doc """
  Executes the before_publish middleware chain.

  Stops execution if any middleware returns :halt.
  Returns the updated middleware configs with any state changes.

  ## Parameters

    - `middleware_configs` - List of `{module, state}` tuples
    - `signals` - List of signals to process
    - `context` - Middleware context with bus_name, timestamp, metadata
    - `timeout_ms` - Timeout in milliseconds for each middleware callback (default: 100)

  ## Returns

    - `{:ok, signals, updated_configs}` on success
    - `{:error, reason}` on failure or timeout
  """
  @spec before_publish([middleware_config()], [Signal.t()], context(), pos_integer()) ::
          {:ok, [Signal.t()], [middleware_config()]} | {:error, term()}
  def before_publish(middleware_configs, signals, context, timeout_ms \\ @default_timeout_ms) do
    middleware_configs
    |> Enum.reduce_while({:ok, signals, []}, fn {module, state}, {:ok, current_signals, acc} ->
      process_before_publish_middleware(module, state, current_signals, acc, context, timeout_ms)
    end)
    |> finalize_before_publish_result()
  end

  defp process_before_publish_middleware(module, state, current_signals, acc, context, timeout_ms) do
    if function_exported?(module, :before_publish, 3) do
      case execute_before_publish_callback(module, state, current_signals, context, timeout_ms) do
        {:cont, {:ok, new_signals, config}} ->
          {:cont, {:ok, new_signals, [config | acc]}}

        {:halt, {:error, reason, config}} ->
          {:halt, {:error, reason, [config | acc]}}

        {:halt, error} ->
          {:halt, error}
      end
    else
      {:cont, {:ok, current_signals, [{module, state} | acc]}}
    end
  end

  defp finalize_before_publish_result(result) do
    case result do
      {:ok, sigs, new_configs} -> {:ok, sigs, Enum.reverse(new_configs)}
      {:error, reason, _configs} -> {:error, reason}
      {:error, _reason} = error -> error
    end
  end

  @doc """
  Executes the after_publish middleware chain.

  This is called for side effects. Returns updated middleware configs.
  Timeout failures in after_publish are logged but do not fail the publish operation.
  """
  @spec after_publish([middleware_config()], [Signal.t()], context(), pos_integer()) ::
          [middleware_config()]
  def after_publish(middleware_configs, signals, context, timeout_ms \\ @default_timeout_ms) do
    Enum.map(middleware_configs, fn {module, state} ->
      process_after_publish_middleware(module, state, signals, context, timeout_ms)
    end)
  end

  defp process_after_publish_middleware(module, state, signals, context, timeout_ms) do
    if function_exported?(module, :after_publish, 3) do
      execute_after_publish_callback(module, state, signals, context, timeout_ms)
    else
      {module, state}
    end
  end

  @doc """
  Executes the before_dispatch middleware chain for a single signal and subscriber.

  Returns the potentially modified signal and updated configs, or indicates if dispatch should be skipped/halted.
  """
  @spec before_dispatch(
          [middleware_config()],
          Signal.t(),
          Subscriber.t(),
          context(),
          pos_integer()
        ) ::
          {:ok, Signal.t(), [middleware_config()]} | :skip | {:error, term()}
  def before_dispatch(
        middleware_configs,
        signal,
        subscriber,
        context,
        timeout_ms \\ @default_timeout_ms
      ) do
    middleware_configs
    |> Enum.reduce_while({:ok, signal, []}, fn {module, state}, {:ok, current_signal, acc} ->
      process_before_dispatch_middleware(
        module,
        state,
        current_signal,
        subscriber,
        acc,
        context,
        timeout_ms
      )
    end)
    |> finalize_before_dispatch_result()
  end

  defp process_before_dispatch_middleware(
         module,
         state,
         current_signal,
         subscriber,
         acc,
         context,
         timeout_ms
       ) do
    if function_exported?(module, :before_dispatch, 4) do
      case execute_before_dispatch_callback(
             module,
             state,
             current_signal,
             subscriber,
             context,
             timeout_ms
           ) do
        {:cont, {:ok, new_signal, config}} ->
          {:cont, {:ok, new_signal, [config | acc]}}

        {:halt, {:skip, config}} ->
          {:halt, {:skip, [config | acc]}}

        {:halt, {:error, reason, config}} ->
          {:halt, {:error, reason, [config | acc]}}

        {:halt, error} ->
          {:halt, error}
      end
    else
      {:cont, {:ok, current_signal, [{module, state} | acc]}}
    end
  end

  defp finalize_before_dispatch_result(result) do
    case result do
      {:ok, sig, new_configs} -> {:ok, sig, Enum.reverse(new_configs)}
      {:skip, _configs} -> :skip
      {:error, reason, _configs} -> {:error, reason}
      {:error, _reason} = error -> error
    end
  end

  @doc """
  Executes the after_dispatch middleware chain.

  This is called for side effects after a signal has been dispatched.
  Returns updated middleware configs. Timeout failures are logged but do not fail the operation.
  """
  @spec after_dispatch(
          [middleware_config()],
          Signal.t(),
          Subscriber.t(),
          Middleware.dispatch_result(),
          context(),
          pos_integer()
        ) :: [middleware_config()]
  def after_dispatch(
        middleware_configs,
        signal,
        subscriber,
        result,
        context,
        timeout_ms \\ @default_timeout_ms
      ) do
    Enum.map(middleware_configs, fn {module, state} ->
      process_after_dispatch_middleware(
        module,
        state,
        signal,
        subscriber,
        result,
        context,
        timeout_ms
      )
    end)
  end

  defp process_after_dispatch_middleware(
         module,
         state,
         signal,
         subscriber,
         result,
         context,
         timeout_ms
       ) do
    if function_exported?(module, :after_dispatch, 5) do
      execute_after_dispatch_callback(
        module,
        state,
        signal,
        subscriber,
        result,
        context,
        timeout_ms
      )
    else
      {module, state}
    end
  end

  @doc """
  Initializes a list of middleware modules with their options.

  Returns a list of {module, state} tuples that can be used in the pipeline.
  """
  @spec init_middleware([{module(), keyword()}]) ::
          {:ok, [middleware_config()]} | {:error, term()}
  def init_middleware(middleware_specs) do
    middleware_specs
    |> Enum.reduce_while({:ok, []}, fn {module, opts}, {:ok, acc} ->
      case module.init(opts) do
        {:ok, state} ->
          {:cont, {:ok, [{module, state} | acc]}}

        {:error, reason} ->
          {:halt, {:error, {:middleware_init_failed, module, reason}}}
      end
    end)
    |> case do
      {:ok, configs} -> {:ok, Enum.reverse(configs)}
      error -> error
    end
  end

  @spec run_with_timeout((-> term()), pos_integer(), module(), context()) :: term()
  defp run_with_timeout(fun, timeout_ms, module, context) do
    task = Task.Supervisor.async_nolink(Jido.Signal.TaskSupervisor, fun)

    case Task.yield(task, timeout_ms) do
      {:ok, result} ->
        result

      {:exit, reason} ->
        {:error,
         Error.execution_error("Middleware crashed", %{module: module, reason: inspect(reason)})}

      nil ->
        case receive_task_exit_reason(task.ref) do
          {:exit, reason} ->
            {:error,
             Error.execution_error("Middleware crashed", %{
               module: module,
               reason: inspect(reason)
             })}

          :timeout ->
            Task.shutdown(task, :brutal_kill)

            Telemetry.execute(
              [:jido, :signal, :middleware, :timeout],
              %{timeout_ms: timeout_ms},
              %{module: module, bus_name: context[:bus_name]}
            )

            {:error,
             Error.execution_error("Middleware timeout", %{module: module, timeout_ms: timeout_ms})}
        end
    end
  end

  defp receive_task_exit_reason(task_ref) do
    receive do
      {:DOWN, ^task_ref, :process, _pid, reason} -> {:exit, reason}
    after
      0 -> :timeout
    end
  end

  # Helper functions for before_publish
  defp execute_before_publish_callback(module, state, current_signals, context, timeout_ms) do
    signals_count = length(current_signals)
    start_time = System.monotonic_time(:microsecond)

    emit_before_publish_start(context, module, signals_count)

    result =
      run_with_timeout(
        fn -> module.before_publish(current_signals, context, state) end,
        timeout_ms,
        module,
        context
      )

    handle_before_publish_result(result, module, state, start_time, context, signals_count)
  end

  defp emit_before_publish_start(context, module, signals_count) do
    Telemetry.execute(
      [:jido, :signal, :middleware, :before_publish, :start],
      %{system_time: System.system_time()},
      %{bus_name: context[:bus_name], module: module, signals_count: signals_count}
    )
  end

  defp handle_before_publish_result(result, module, _state, start_time, context, signals_count) do
    duration_us = System.monotonic_time(:microsecond) - start_time

    case result do
      {:cont, new_signals, new_state} ->
        emit_before_publish_stop(context, module, signals_count, duration_us)
        {:cont, {:ok, new_signals, {module, new_state}}}

      {:halt, reason, new_state} ->
        emit_before_publish_stop(context, module, signals_count, duration_us)
        {:halt, {:error, reason, {module, new_state}}}

      {:error, _reason} = error ->
        emit_before_publish_exception(context, module, signals_count, duration_us)
        {:halt, error}
    end
  end

  defp emit_before_publish_stop(context, module, signals_count, duration_us) do
    Telemetry.execute(
      [:jido, :signal, :middleware, :before_publish, :stop],
      %{duration_us: duration_us},
      %{bus_name: context[:bus_name], module: module, signals_count: signals_count}
    )
  end

  defp emit_before_publish_exception(context, module, signals_count, duration_us) do
    Telemetry.execute(
      [:jido, :signal, :middleware, :before_publish, :exception],
      %{duration_us: duration_us},
      %{bus_name: context[:bus_name], module: module, signals_count: signals_count}
    )
  end

  # Helper functions for after_publish
  defp execute_after_publish_callback(module, state, signals, context, timeout_ms) do
    signals_count = length(signals)
    start_time = System.monotonic_time(:microsecond)

    result =
      run_with_timeout(
        fn -> module.after_publish(signals, context, state) end,
        timeout_ms,
        module,
        context
      )

    handle_after_publish_result(result, module, state, start_time, context, signals_count)
  end

  defp handle_after_publish_result(result, module, state, start_time, context, signals_count) do
    case result do
      {:cont, _signals, new_state} ->
        duration_us = System.monotonic_time(:microsecond) - start_time
        emit_after_publish_stop(context, module, signals_count, duration_us)
        {module, new_state}

      {:error, _reason} ->
        {module, state}

      _ ->
        {module, state}
    end
  end

  defp emit_after_publish_stop(context, module, signals_count, duration_us) do
    Telemetry.execute(
      [:jido, :signal, :middleware, :after_publish, :stop],
      %{duration_us: duration_us},
      %{bus_name: context[:bus_name], module: module, signals_count: signals_count}
    )
  end

  # Helper functions for before_dispatch
  defp execute_before_dispatch_callback(module, state, signal, subscriber, context, timeout_ms) do
    start_time = System.monotonic_time(:microsecond)

    emit_before_dispatch_start(context, module, signal, subscriber)

    result =
      run_with_timeout(
        fn -> module.before_dispatch(signal, subscriber, context, state) end,
        timeout_ms,
        module,
        context
      )

    handle_before_dispatch_result(result, module, start_time, context, signal, subscriber)
  end

  defp emit_before_dispatch_start(context, module, signal, subscriber) do
    Telemetry.execute(
      [:jido, :signal, :middleware, :before_dispatch, :start],
      %{system_time: System.system_time()},
      %{
        bus_name: context[:bus_name],
        module: module,
        signal_id: signal.id,
        subscription_id: subscriber.id
      }
    )
  end

  defp handle_before_dispatch_result(result, module, start_time, context, signal, subscriber) do
    duration_us = System.monotonic_time(:microsecond) - start_time
    telemetry_meta = build_dispatch_telemetry_meta(context, module, signal, subscriber)

    case result do
      {:cont, new_signal, new_state} ->
        emit_before_dispatch_telemetry(:stop, duration_us, telemetry_meta)
        {:cont, {:ok, new_signal, {module, new_state}}}

      {:skip, new_state} ->
        emit_before_dispatch_telemetry(:skip, duration_us, telemetry_meta)
        {:halt, {:skip, {module, new_state}}}

      {:halt, reason, new_state} ->
        emit_before_dispatch_telemetry(:stop, duration_us, telemetry_meta)
        {:halt, {:error, reason, {module, new_state}}}

      {:error, _reason} = error ->
        {:halt, error}
    end
  end

  defp build_dispatch_telemetry_meta(context, module, signal, subscriber) do
    %{
      bus_name: context[:bus_name],
      module: module,
      signal_id: signal.id,
      subscription_id: subscriber.id
    }
  end

  defp emit_before_dispatch_telemetry(event, duration_us, meta) do
    Telemetry.execute(
      [:jido, :signal, :middleware, :before_dispatch, event],
      %{duration_us: duration_us},
      meta
    )
  end

  # Helper functions for after_dispatch
  defp execute_after_dispatch_callback(
         module,
         state,
         signal,
         subscriber,
         result,
         context,
         timeout_ms
       ) do
    start_time = System.monotonic_time(:microsecond)

    callback_result =
      run_with_timeout(
        fn -> module.after_dispatch(signal, subscriber, result, context, state) end,
        timeout_ms,
        module,
        context
      )

    handle_after_dispatch_result(
      callback_result,
      module,
      state,
      start_time,
      context,
      signal,
      subscriber
    )
  end

  defp handle_after_dispatch_result(
         callback_result,
         module,
         state,
         start_time,
         context,
         signal,
         subscriber
       ) do
    case callback_result do
      {:cont, new_state} ->
        duration_us = System.monotonic_time(:microsecond) - start_time
        emit_after_dispatch_stop(context, module, signal, subscriber, duration_us)
        {module, new_state}

      {:error, _reason} ->
        {module, state}

      _ ->
        {module, state}
    end
  end

  defp emit_after_dispatch_stop(context, module, signal, subscriber, duration_us) do
    Telemetry.execute(
      [:jido, :signal, :middleware, :after_dispatch, :stop],
      %{duration_us: duration_us},
      %{
        bus_name: context[:bus_name],
        module: module,
        signal_id: signal.id,
        subscription_id: subscriber.id
      }
    )
  end
end
