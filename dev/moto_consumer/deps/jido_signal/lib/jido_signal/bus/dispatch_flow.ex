defmodule Jido.Signal.Bus.DispatchFlow do
  @moduledoc false

  alias Jido.Signal.Bus.MiddlewarePipeline
  alias Jido.Signal.Bus.Subscriber
  alias Jido.Signal.Telemetry

  require Logger

  @type middleware_config :: {module(), term()}
  @type dispatch_fun :: (Jido.Signal.t(), Subscriber.t() -> term())

  @spec dispatch(
          [middleware_config()],
          Jido.Signal.t(),
          Subscriber.t(),
          String.t(),
          map(),
          pos_integer(),
          dispatch_fun(),
          keyword()
        ) :: {:ok, [middleware_config()], term()} | {:skip, [middleware_config()]}
  def dispatch(
        middleware,
        signal,
        subscription,
        subscription_id,
        context,
        timeout_ms,
        dispatch_fun,
        opts
      ) do
    bus_name = Keyword.fetch!(opts, :bus_name)
    partition_id = Keyword.get(opts, :partition_id)

    emit_before_dispatch_telemetry(bus_name, signal, subscription_id, subscription, partition_id)

    case MiddlewarePipeline.before_dispatch(
           middleware,
           signal,
           subscription,
           context,
           timeout_ms
         ) do
      {:ok, processed_signal, updated_middleware} ->
        result = dispatch_fun.(processed_signal, subscription)

        emit_after_dispatch_telemetry(
          bus_name,
          processed_signal,
          subscription_id,
          subscription,
          result,
          partition_id
        )

        new_middleware =
          MiddlewarePipeline.after_dispatch(
            updated_middleware,
            processed_signal,
            subscription,
            result,
            context,
            timeout_ms
          )

        {:ok, new_middleware, result}

      :skip ->
        emit_dispatch_skipped_telemetry(
          bus_name,
          signal,
          subscription_id,
          subscription,
          partition_id
        )

        {:skip, middleware}

      {:error, reason} ->
        emit_dispatch_error_telemetry(
          bus_name,
          signal,
          subscription_id,
          subscription,
          reason,
          partition_id
        )

        Logger.warning("Middleware halted dispatch for signal #{signal.id}: #{inspect(reason)}")
        {:skip, middleware}
    end
  end

  defp emit_before_dispatch_telemetry(
         bus_name,
         signal,
         subscription_id,
         subscription,
         partition_id
       ) do
    Telemetry.execute(
      [:jido, :signal, :bus, :before_dispatch],
      %{timestamp: System.monotonic_time(:microsecond)},
      dispatch_metadata(
        bus_name,
        signal,
        subscription_id,
        subscription,
        %{signal: signal, subscription: subscription},
        partition_id
      )
    )
  end

  defp emit_after_dispatch_telemetry(
         bus_name,
         signal,
         subscription_id,
         subscription,
         result,
         partition_id
       ) do
    Telemetry.execute(
      [:jido, :signal, :bus, :after_dispatch],
      %{timestamp: System.monotonic_time(:microsecond)},
      dispatch_metadata(
        bus_name,
        signal,
        subscription_id,
        subscription,
        %{dispatch_result: result, signal: signal, subscription: subscription},
        partition_id
      )
    )
  end

  defp emit_dispatch_skipped_telemetry(
         bus_name,
         signal,
         subscription_id,
         subscription,
         partition_id
       ) do
    Telemetry.execute(
      [:jido, :signal, :bus, :dispatch_skipped],
      %{timestamp: System.monotonic_time(:microsecond)},
      dispatch_metadata(
        bus_name,
        signal,
        subscription_id,
        subscription,
        %{reason: :middleware_skip, signal: signal, subscription: subscription},
        partition_id
      )
    )
  end

  defp emit_dispatch_error_telemetry(
         bus_name,
         signal,
         subscription_id,
         subscription,
         reason,
         partition_id
       ) do
    Telemetry.execute(
      [:jido, :signal, :bus, :dispatch_error],
      %{timestamp: System.monotonic_time(:microsecond)},
      dispatch_metadata(
        bus_name,
        signal,
        subscription_id,
        subscription,
        %{error: reason, signal: signal, subscription: subscription},
        partition_id
      )
    )
  end

  defp dispatch_metadata(
         bus_name,
         signal,
         subscription_id,
         subscription,
         extra,
         partition_id
       ) do
    metadata =
      Map.merge(
        %{
          bus_name: bus_name,
          signal_id: signal.id,
          signal_type: signal.type,
          subscription_id: subscription_id,
          subscription_path: subscription.path
        },
        extra
      )

    maybe_put_partition_id(metadata, partition_id)
  end

  defp maybe_put_partition_id(metadata, nil), do: metadata

  defp maybe_put_partition_id(metadata, partition_id),
    do: Map.put(metadata, :partition_id, partition_id)
end
