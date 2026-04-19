defmodule Jido.Signal.Dispatch.CircuitBreaker do
  @moduledoc """
  Circuit breaker wrapper using :fuse for dispatch adapters.

  Circuits are per-adapter-type (e.g., one circuit for all HTTP calls, one for all webhook calls).
  This provides bulk fault isolation without the overhead of per-endpoint circuits.

  ## Configuration

  Default settings:
  - 5 failures in 10 seconds triggers the circuit to open
  - 30 second reset time before trying again

  ## Usage

      # Install circuit for an adapter type
      :ok = CircuitBreaker.install(:http)

      # Run a function with circuit breaker protection
      case CircuitBreaker.run(:http, fn -> make_request() end) do
        :ok -> :ok
        {:ok, response} -> {:ok, response}
        {:error, :circuit_open} -> {:error, :circuit_open}
        {:error, reason} -> {:error, reason}
      end

      # Check status
      :ok = CircuitBreaker.status(:http)  # or :blown

      # Reset manually
      :ok = CircuitBreaker.reset(:http)
  """

  alias Jido.Signal.Telemetry

  require Logger

  @default_max_failures 5
  @default_window_ms 10_000
  @default_reset_ms 30_000

  @doc """
  Installs a circuit breaker for the given adapter type.

  Should be called once at application startup for each adapter type that needs protection.

  ## Parameters

  * `adapter_type` - Atom identifying the adapter (e.g., `:http`, `:webhook`)
  * `opts` - Optional configuration:
    * `:strategy` - Fuse strategy, defaults to `{:standard, 5, 10_000}` (5 failures in 10 seconds)
    * `:refresh` - Reset time in milliseconds, defaults to 30_000

  ## Returns

  * `:ok` - Circuit installed successfully
  * `{:error, term()}` - Installation failed
  """
  @spec install(atom(), keyword()) :: :ok | {:error, term()}
  def install(adapter_type, opts \\ []) do
    strategy =
      Keyword.get(opts, :strategy, {:standard, @default_max_failures, @default_window_ms})

    refresh = Keyword.get(opts, :refresh, @default_reset_ms)
    fuse_opts = {strategy, {:reset, refresh}}

    case fuse_call(:install, [fuse_name(adapter_type), fuse_opts]) do
      :ok -> :ok
      :reset -> :ok
      {:error, :already_installed} -> :ok
      error -> error
    end
  end

  @doc """
  Runs a function with circuit breaker protection.

  Returns the function result if the circuit is closed, or `{:error, :circuit_open}` if open.
  On failure, the fuse is melted (failure recorded).

  ## Parameters

  * `adapter_type` - Atom identifying the adapter
  * `fun` - Zero-arity function to execute

  ## Returns

  * Result of `fun` if circuit is closed and execution succeeds
  * `{:error, :circuit_open}` if circuit is open
  * `{:error, {:exception, message}}` if function raises
  """
  @spec run(atom(), (-> any())) :: any() | {:error, :circuit_open}
  def run(adapter_type, fun) do
    case fuse_call(:ask, [fuse_name(adapter_type), :sync]) do
      :ok ->
        try do
          result = fun.()

          case result do
            :ok ->
              result

            {:ok, _} = ok ->
              ok

            {:error, _} = error ->
              _ = fuse_call(:melt, [fuse_name(adapter_type)])
              emit_melt_telemetry(adapter_type)
              error
          end
        rescue
          e ->
            _ = fuse_call(:melt, [fuse_name(adapter_type)])
            emit_melt_telemetry(adapter_type)
            {:error, {:exception, Exception.message(e)}}
        end

      :blown ->
        emit_rejected_telemetry(adapter_type)
        {:error, :circuit_open}
    end
  end

  @doc """
  Returns the current status of a circuit.

  ## Parameters

  * `adapter_type` - Atom identifying the adapter

  ## Returns

  * `:ok` - Circuit is closed (healthy)
  * `:blown` - Circuit is open (failing)
  """
  @spec status(atom()) :: :ok | :blown
  def status(adapter_type) do
    case fuse_call(:ask, [fuse_name(adapter_type), :sync]) do
      :ok -> :ok
      :blown -> :blown
    end
  end

  @doc """
  Resets a circuit, allowing requests through again.

  ## Parameters

  * `adapter_type` - Atom identifying the adapter

  ## Returns

  * `:ok` - Circuit reset successfully
  """
  @spec reset(atom()) :: :ok
  def reset(adapter_type) do
    _ = fuse_call(:reset, [fuse_name(adapter_type)])
    emit_reset_telemetry(adapter_type)
    :ok
  end

  @doc """
  Checks if a circuit is installed.

  ## Parameters

  * `adapter_type` - Atom identifying the adapter

  ## Returns

  * `true` - Circuit is installed
  * `false` - Circuit is not installed
  """
  @spec installed?(atom()) :: boolean()
  def installed?(adapter_type) do
    case fuse_call(:ask, [fuse_name(adapter_type), :sync]) do
      :ok -> true
      :blown -> true
      {:error, :not_found} -> false
    end
  end

  defp fuse_call(function_name, args) when is_atom(function_name) and is_list(args) do
    apply(:fuse, function_name, args)
  end

  defp fuse_name(adapter_type) when is_atom(adapter_type) do
    :"jido_dispatch_#{adapter_type}"
  end

  defp emit_melt_telemetry(adapter_type) do
    Telemetry.execute(
      [:jido, :dispatch, :circuit, :melt],
      %{},
      %{adapter: adapter_type}
    )
  end

  defp emit_rejected_telemetry(adapter_type) do
    Telemetry.execute(
      [:jido, :dispatch, :circuit, :rejected],
      %{},
      %{adapter: adapter_type}
    )
  end

  defp emit_reset_telemetry(adapter_type) do
    Telemetry.execute(
      [:jido, :dispatch, :circuit, :reset],
      %{},
      %{adapter: adapter_type}
    )
  end
end
