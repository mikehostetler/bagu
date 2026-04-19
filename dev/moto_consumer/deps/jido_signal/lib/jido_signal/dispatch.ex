defmodule Jido.Signal.Dispatch do
  @moduledoc """
  A flexible signal dispatching system that routes signals to various destinations using configurable adapters.

  The Dispatch module serves as the central hub for signal delivery in the Jido system. It provides a unified
  interface for sending signals to different destinations through various adapters. Each adapter implements
  specific delivery mechanisms suited for different use cases.

  ## Built-in Adapters

  The following adapters are provided out of the box:

  * `:pid` - Direct delivery to a specific process (see `Jido.Signal.Dispatch.PidAdapter`)
  * `:bus` - Delivery to a signal bus via `Jido.Signal.Bus`
  * `:named` - Delivery to a named process (see `Jido.Signal.Dispatch.Named`)
  * `:pubsub` - Delivery via PubSub mechanism (see `Jido.Signal.Dispatch.PubSub`)
  * `:logger` - Log signals using Logger (see `Jido.Signal.Dispatch.LoggerAdapter`)
  * `:console` - Print signals to console (see `Jido.Signal.Dispatch.ConsoleAdapter`)
  * `:noop` - No-op adapter for testing/development (see `Jido.Signal.Dispatch.NoopAdapter`)
  * `:http` - HTTP requests using :httpc (see `Jido.Signal.Dispatch.Http`)
  * `:webhook` - Webhook delivery with signatures (see `Jido.Signal.Dispatch.Webhook`)

  ## Configuration

  Each adapter requires specific configuration options. A dispatch configuration is a tuple of
  `{adapter_type, options}` where:

  * `adapter_type` - One of the built-in adapter types above or a custom module implementing the `Jido.Signal.Dispatch.Adapter` behaviour
  * `options` - Keyword list of options specific to the chosen adapter

  Multiple dispatch configurations can be provided as a list to send signals to multiple destinations.

  ## Dispatch Modes

  The module supports three dispatch modes:

  1. Synchronous (via `dispatch/2`) - Fire-and-forget dispatch that returns when all dispatches complete
  2. Asynchronous (via `dispatch_async/2`) - Returns immediately with a task that can be monitored
  3. Batched (via `dispatch_batch/3`) - Handles large numbers of dispatches in configurable batches

  ## Concurrency

  When dispatching to multiple targets (via a list of configs), the dispatch system processes
  them in parallel using `Task.Supervisor.async_stream/3`. The maximum concurrency can be
  configured at compile-time or runtime:

      # In config.exs (compile-time)
      config :jido, :dispatch_max_concurrency, 16

      # Default: 8 concurrent dispatches

  This parallel processing significantly improves throughput for multiple targets. For example,
  dispatching to 10 targets with 100ms latency each completes in ~200ms (with default concurrency)
  instead of ~1000ms sequentially.

  ## Error Handling

  **BREAKING CHANGE in behavior:** When dispatching to multiple targets (list of configs),
  `dispatch/2` now aggregates all errors instead of returning only the first error:

  - Single config: `dispatch(signal, config)` returns `:ok` or `{:error, reason}`
  - Multiple configs: `dispatch(signal, configs)` returns `:ok` or `{:error, [reason1, reason2, ...]}`

  The batch dispatch function `dispatch_batch/3` continues to return indexed errors as before:
  `{:error, [{index, reason}, ...]}`.

  ## Reserved Options

  The following option keys are reserved for internal use and should not be used in dispatch configurations:

  * `:__validated__` - Marks pre-validated configurations (internal optimization flag)

  ## Deprecated

  * `batch_size` option in `dispatch_batch/3` - Kept for backwards compatibility but no longer used.
    All dispatches now use the same parallel processing with `max_concurrency` control.

  ## Examples

      # Synchronous dispatch
      config = {:pid, [target: pid, delivery_mode: :async]}
      :ok = Dispatch.dispatch(signal, config)

      # Asynchronous dispatch
      {:ok, task} = Dispatch.dispatch_async(signal, config)
      :ok = Task.await(task)

      # Batch dispatch
      configs = List.duplicate({:pid, [target: pid]}, 1000)
      :ok = Dispatch.dispatch_batch(signal, configs, max_concurrency: 20)

      # Multiple targets with parallel dispatch
      configs = [
        {:pid, [target: pid1]},
        {:http, [url: "https://api.example.com/webhook"]},
        {:pubsub, [target: :my_pubsub, topic: "events"]}
      ]
      # Returns :ok or {:error, [error1, error2, ...]}
      Dispatch.dispatch(signal, configs)

      # HTTP dispatch
      config = {:http, [
        url: "https://api.example.com/events",
        method: :post,
        headers: [{"x-api-key", "secret"}]
      ]}
      :ok = Dispatch.dispatch(signal, config)

      # Webhook dispatch
      config = {:webhook, [
        url: "https://api.example.com/webhook",
        secret: "webhook_secret",
        event_type_map: %{"user:created" => "user.created"}
      ]}
      :ok = Dispatch.dispatch(signal, config)
  """

  alias Jido.Signal.Error
  alias Jido.Signal.Telemetry

  @type adapter ::
          :pid
          | :bus
          | :named
          | :pubsub
          | :logger
          | :console
          | :noop
          | :http
          | :webhook
          | nil
          | module()
  @type dispatch_config :: {adapter(), Keyword.t()}
  @type dispatch_configs :: dispatch_config() | [dispatch_config()]
  @type runtime_opts :: [task_supervisor: pid() | atom()]
  @type batch_opts :: [
          batch_size: pos_integer(),
          max_concurrency: pos_integer(),
          task_supervisor: pid() | atom()
        ]

  @default_batch_size 50
  @default_max_concurrency 5
  @default_dispatch_max_concurrency Application.compile_env(
                                      :jido,
                                      :dispatch_max_concurrency,
                                      8
                                    )
  @normalize_errors_compile_time Application.compile_env(:jido, :normalize_dispatch_errors, false)

  @builtin_adapters %{
    pid: Jido.Signal.Dispatch.PidAdapter,
    named: Jido.Signal.Dispatch.Named,
    pubsub: Jido.Signal.Dispatch.PubSub,
    bus: Jido.Signal.Dispatch.Bus,
    logger: Jido.Signal.Dispatch.LoggerAdapter,
    console: Jido.Signal.Dispatch.ConsoleAdapter,
    noop: Jido.Signal.Dispatch.NoopAdapter,
    http: Jido.Signal.Dispatch.Http,
    webhook: Jido.Signal.Dispatch.Webhook,
    nil: nil
  }

  @doc """
  Validates a dispatch configuration without executing the dispatch.

  This is useful for pre-validating configurations before dispatch time, or for testing
  adapter configurations. Validation is automatically performed during dispatch, but
  this function allows explicit validation for debugging or testing purposes.

  ## Parameters

  - `config` - Either a single dispatch configuration tuple or a list of dispatch configurations

  ## Returns

  - `{:ok, config}` if the configuration is valid
  - `{:error, reason}` if the configuration is invalid

  ## Examples

      # Single config
      iex> config = {:pid, [target: self(), delivery_mode: :async]}
      iex> Jido.Signal.Dispatch.validate_opts(config)
      {:ok, ^config}

      # Multiple configs
      iex> config = [
      ...>   {:bus, [target: :default_bus]},
      ...>   {:pubsub, [target: :audit_pubsub, topic: "audit"]}
      ...> ]
      iex> Jido.Signal.Dispatch.validate_opts(config)
      {:ok, ^config}

      # Pre-validation for testing
      {:ok, validated} = Dispatch.validate_opts({:pid, [target: pid]})
      # Use validated config later...
  """
  @spec validate_opts(dispatch_configs()) :: {:ok, dispatch_configs()} | {:error, term()}
  # Handle single dispatcher config
  def validate_opts({adapter, opts} = config) when is_atom(adapter) and is_list(opts) do
    case validate_single_config(config) do
      {:ok, {adapter, validated_opts}} ->
        # Remove internal marker before returning to user
        {:ok, {adapter, Keyword.delete(validated_opts, :__validated__)}}

      error ->
        error
    end
  end

  # Handle list of dispatchers
  def validate_opts(configs) when is_list(configs) do
    results = Enum.map(configs, &validate_single_config/1)

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil ->
        cleaned_results =
          Enum.map(results, fn {:ok, {adapter, opts}} ->
            {adapter, Keyword.delete(opts, :__validated__)}
          end)

        {:ok, cleaned_results}

      error ->
        error
    end
  end

  def validate_opts(invalid_config) do
    if should_normalize_errors?() do
      {:error,
       Error.validation_error(
         "Invalid dispatch configuration",
         %{field: "dispatch_config", value: invalid_config, reason: :invalid_dispatch_config}
       )}
    else
      {:error, :invalid_dispatch_config}
    end
  end

  @doc """
  Dispatches a signal using the provided configuration.

  This is a synchronous operation that returns when all dispatches complete.
  For asynchronous dispatch, use `dispatch_async/2`.
  For batch dispatch, use `dispatch_batch/3`.

  When dispatching to multiple targets (list of configs), dispatches are executed in parallel
  with configurable concurrency (default: 8 concurrent tasks).

  ## Parameters

  - `signal` - The signal to dispatch
  - `config` - Either a single dispatch configuration tuple or a list of configurations

  ## Returns

  - `:ok` - All dispatches succeeded
  - `{:error, reason}` - Single config dispatch failed
  - `{:error, [reason1, reason2, ...]}` - One or more multi-config dispatches failed (aggregated errors)

  ## Examples

      # Single destination
      iex> config = {:pid, [target: pid, delivery_mode: :async]}
      iex> Jido.Signal.Dispatch.dispatch(signal, config)
      :ok

      # Multiple destinations (executed in parallel)
      iex> config = [
      ...>   {:bus, [target: :default_bus]},
      ...>   {:pubsub, [target: :audit, topic: "audit"]}
      ...> ]
      iex> Jido.Signal.Dispatch.dispatch(signal, config)
      :ok

      # Error aggregation for multiple targets
      iex> config = [
      ...>   {:pid, [target: pid1]},
      ...>   {:invalid_adapter, []},
      ...>   {:pid, [target: pid2]}
      ...> ]
      iex> Jido.Signal.Dispatch.dispatch(signal, config)
      {:error, [%Jido.Signal.Error{...}]}
  """
  @spec dispatch(Jido.Signal.t(), dispatch_configs()) :: :ok | {:error, term()}
  @spec dispatch(Jido.Signal.t(), dispatch_configs(), runtime_opts()) :: :ok | {:error, term()}
  def dispatch(signal, config) do
    dispatch(signal, config, [])
  end

  # Handle single dispatcher
  def dispatch(signal, {adapter, opts} = config, _runtime_opts)
      when is_atom(adapter) and is_list(opts) do
    dispatch_single(signal, config)
  end

  # Handle multiple dispatchers
  def dispatch(signal, configs, runtime_opts) when is_list(configs) do
    task_supervisor = task_supervisor(runtime_opts)

    results =
      Task.Supervisor.async_stream(
        task_supervisor,
        configs,
        fn config -> dispatch_single(signal, config) end,
        max_concurrency: @default_dispatch_max_concurrency,
        ordered: true,
        timeout: :infinity
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, reason} -> {:error, reason}
      end)

    # Collect ALL errors instead of returning first error
    errors =
      Enum.filter(results, &match?({:error, _}, &1))
      |> Enum.map(fn {:error, reason} -> reason end)

    case errors do
      [] -> :ok
      _ -> {:error, errors}
    end
  end

  def dispatch(_signal, _config, _runtime_opts) do
    {:error, :invalid_dispatch_config}
  end

  @doc """
  Dispatches a signal asynchronously using the provided configuration.

  Returns immediately with a task that can be monitored for completion.

  ## Parameters

  - `signal` - The signal to dispatch
  - `config` - Either a single dispatch configuration tuple or a list of configurations

  ## Returns

  - `{:ok, task}` where task is a Task that can be awaited
  - `{:error, reason}` if the configuration is invalid

  ## Examples

      {:ok, task} = Dispatch.dispatch_async(signal, config)
      :ok = Task.await(task)
  """
  @spec dispatch_async(Jido.Signal.t(), dispatch_configs()) :: {:ok, Task.t()} | {:error, term()}
  @spec dispatch_async(Jido.Signal.t(), dispatch_configs(), runtime_opts()) ::
          {:ok, Task.t()} | {:error, term()}
  def dispatch_async(signal, config) do
    dispatch_async(signal, config, [])
  end

  def dispatch_async(signal, config, runtime_opts) do
    task_supervisor = task_supervisor(runtime_opts)

    case validate_opts(config) do
      {:ok, validated_config} ->
        task =
          Task.Supervisor.async_nolink(task_supervisor, fn ->
            dispatch(signal, validated_config, runtime_opts)
          end)

        {:ok, task}

      error ->
        error
    end
  end

  @doc """
  Dispatches a signal to multiple destinations in batches.

  This is useful when dispatching to a large number of destinations to avoid
  overwhelming the system. The dispatches are processed with configurable concurrency.

  ## Parameters

  - `signal` - The signal to dispatch
  - `configs` - List of dispatch configurations
  - `opts` - Batch options:
    * `:batch_size` - **Deprecated** (kept for backwards compatibility, no longer used)
    * `:max_concurrency` - Maximum number of concurrent dispatches (default: #{@default_max_concurrency})

  ## Returns

  - `:ok` if all dispatches succeed
  - `{:error, errors}` where errors is a list of `{index, reason}` tuples

  ## Examples

      configs = List.duplicate({:pid, [target: pid]}, 1000)
      :ok = Dispatch.dispatch_batch(signal, configs, max_concurrency: 20)
  """
  @spec dispatch_batch(Jido.Signal.t(), [dispatch_config()], batch_opts()) ::
          :ok | {:error, [{non_neg_integer(), term()}]}
  def dispatch_batch(signal, configs, opts \\ []) when is_list(configs) do
    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)
    max_concurrency = Keyword.get(opts, :max_concurrency, @default_max_concurrency)
    task_supervisor = Keyword.get(opts, :task_supervisor, Jido.Signal.TaskSupervisor)

    validation_results = validate_configs_with_index(configs)
    {valid_configs, validation_errors} = split_validation_results(validation_results)

    validated_configs_with_idx = extract_validated_configs(valid_configs)

    dispatch_results =
      process_batches(
        signal,
        validated_configs_with_idx,
        batch_size,
        max_concurrency,
        task_supervisor
      )

    validation_errors = extract_validation_errors(validation_errors)
    dispatch_errors = extract_dispatch_errors(dispatch_results)

    combine_results(validation_errors, dispatch_errors)
  end

  # Batch processing helpers

  defp validate_configs_with_index(configs) do
    configs_with_index = Enum.with_index(configs)

    Enum.map(configs_with_index, fn {config, idx} ->
      case validate_single_config(config) do
        {:ok, validated_config} -> {:ok, {validated_config, idx}}
        {:error, reason} -> {:error, {idx, reason}}
      end
    end)
  end

  defp split_validation_results(validation_results) do
    Enum.split_with(validation_results, fn
      {:ok, _} -> true
      {:error, _} -> false
    end)
  end

  defp extract_validated_configs(valid_configs) do
    Enum.map(valid_configs, fn {:ok, {config, idx}} -> {config, idx} end)
  end

  defp process_batches(
         signal,
         validated_configs_with_idx,
         _batch_size,
         max_concurrency,
         task_supervisor
       ) do
    # Single stream over all configs (batch_size is now a no-op for backwards compat)
    Task.Supervisor.async_stream(
      task_supervisor,
      validated_configs_with_idx,
      fn {config, original_idx} ->
        case dispatch_single(signal, config) do
          :ok -> {:ok, original_idx}
          {:error, reason} -> {:error, {original_idx, reason}}
        end
      end,
      max_concurrency: max_concurrency,
      ordered: true,
      timeout: :infinity
    )
    |> Enum.map(fn {:ok, result} -> result end)
  end

  defp extract_validation_errors(validation_errors) do
    Enum.map(validation_errors, fn {:error, error} -> error end)
  end

  defp extract_dispatch_errors(dispatch_results) do
    Enum.reduce(dispatch_results, [], fn
      {:error, error}, acc -> [error | acc]
      {:ok, _}, acc -> acc
    end)
  end

  defp combine_results(validation_errors, dispatch_errors) do
    case {validation_errors, dispatch_errors} do
      {[], []} -> :ok
      {errors, []} -> {:error, Enum.reverse(errors)}
      {[], errors} -> {:error, Enum.reverse(errors)}
      {val_errs, disp_errs} -> {:error, Enum.reverse(val_errs ++ disp_errs)}
    end
  end

  defp task_supervisor(runtime_opts) when is_list(runtime_opts) do
    Keyword.get(runtime_opts, :task_supervisor, Jido.Signal.TaskSupervisor)
  end

  # Private helpers

  defp normalize_error(reason, adapter, config) when is_atom(reason) do
    if should_normalize_errors?() do
      {:error,
       Error.dispatch_error(
         "Signal dispatch failed",
         %{adapter: adapter, reason: reason, config: config}
       )}
    else
      {:error, reason}
    end
  end

  defp normalize_error(reason, adapter, config) do
    if should_normalize_errors?() do
      {:error,
       Error.dispatch_error(
         "Signal dispatch failed",
         %{adapter: adapter, reason: reason, config: config}
       )}
    else
      {:error, reason}
    end
  end

  defp normalize_validation_error(reason, adapter, config) when is_atom(reason) do
    if should_normalize_errors?() do
      {:error,
       Error.validation_error(
         "Invalid adapter configuration",
         %{field: "config", value: config, adapter: adapter, reason: reason}
       )}
    else
      {:error, reason}
    end
  end

  defp normalize_validation_error(reason, adapter, config) do
    if should_normalize_errors?() do
      {:error,
       Error.validation_error(
         "Invalid adapter configuration",
         %{field: "config", value: config, adapter: adapter, reason: reason}
       )}
    else
      {:error, reason}
    end
  end

  defp should_normalize_errors? do
    @normalize_errors_compile_time or
      Application.get_env(:jido, :normalize_dispatch_errors, false)
  end

  defp get_target_from_opts(opts) do
    cond do
      target = Keyword.get(opts, :target) -> target
      url = Keyword.get(opts, :url) -> url
      pid = Keyword.get(opts, :pid) -> pid
      name = Keyword.get(opts, :name) -> name
      topic = Keyword.get(opts, :topic) -> topic
      true -> :unknown
    end
  end

  defp validate_single_config({nil, opts}) when is_list(opts) do
    {:ok, {nil, opts}}
  end

  defp validate_single_config({adapter, opts}) when is_atom(adapter) and is_list(opts) do
    with {:ok, adapter_module} <- resolve_adapter(adapter),
         {:ok, validated_opts} <- validate_adapter_opts(adapter_module, opts, adapter) do
      {:ok, {adapter, Keyword.put(validated_opts, :__validated__, true)}}
    else
      {:error, reason} -> normalize_validation_error(reason, adapter, {adapter, opts})
    end
  end

  # Validates options with the adapter module, handling nil adapter case
  defp validate_adapter_opts(nil, opts, _adapter), do: {:ok, opts}

  defp validate_adapter_opts(adapter_module, opts, _adapter) do
    adapter_module.validate_opts(opts)
  end

  defp dispatch_single(_signal, {nil, _opts}), do: :ok

  defp dispatch_single(signal, {adapter, opts}) do
    start_time = System.monotonic_time(:millisecond)

    signal_type =
      case signal do
        %{type: type} -> type
        _ -> :unknown
      end

    metadata = %{
      adapter: adapter,
      signal_type: signal_type,
      target: get_target_from_opts(opts)
    }

    Telemetry.execute([:jido, :dispatch, :start], %{}, metadata)

    result = do_dispatch_single(signal, {adapter, opts})

    end_time = System.monotonic_time(:millisecond)
    latency_ms = end_time - start_time
    success = match?(:ok, result)

    measurements = %{latency_ms: latency_ms}
    metadata = Map.put(metadata, :success?, success)

    if success do
      Telemetry.execute([:jido, :dispatch, :stop], measurements, metadata)
    else
      Telemetry.execute([:jido, :dispatch, :exception], measurements, metadata)
    end

    result
  end

  defp do_dispatch_single(signal, {adapter, opts}) do
    case resolve_adapter(adapter) do
      {:ok, adapter_module} ->
        do_dispatch_with_adapter(signal, adapter_module, {adapter, opts})

      {:error, reason} ->
        normalize_error(reason, adapter, {adapter, opts})
    end
  end

  defp do_dispatch_with_adapter(_signal, nil, {_adapter, _opts}), do: :ok

  defp do_dispatch_with_adapter(signal, adapter_module, {adapter, opts}) do
    # Skip validation if already validated
    if Keyword.get(opts, :__validated__, false) do
      dispatch_deliver(signal, adapter_module, adapter, opts)
    else
      case adapter_module.validate_opts(opts) do
        {:ok, validated_opts} ->
          dispatch_deliver(signal, adapter_module, adapter, validated_opts)

        {:error, reason} ->
          normalize_error(reason, adapter, {adapter, opts})
      end
    end
  end

  defp dispatch_deliver(signal, adapter_module, adapter, opts) do
    case adapter_module.deliver(signal, opts) do
      :ok -> :ok
      {:error, reason} -> normalize_error(reason, adapter, {adapter, opts})
    end
  end

  defp resolve_adapter(nil), do: {:ok, nil}

  defp resolve_adapter(adapter) when is_atom(adapter) do
    case Map.fetch(@builtin_adapters, adapter) do
      {:ok, module} when not is_nil(module) ->
        {:ok, module}

      {:ok, nil} ->
        {:error, :no_adapter_needed}

      :error ->
        if Code.ensure_loaded?(adapter) and function_exported?(adapter, :deliver, 2) do
          {:ok, adapter}
        else
          {:error,
           "#{inspect(adapter)} is not a valid adapter - must be one of :pid, :named, :pubsub, :bus, :logger, :console, :noop, :http, :webhook or a module implementing deliver/2"}
        end
    end
  end
end
