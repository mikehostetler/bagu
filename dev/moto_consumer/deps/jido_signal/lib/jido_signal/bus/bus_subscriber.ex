defmodule Jido.Signal.Bus.Subscriber do
  @moduledoc """
  Defines the subscriber model and subscription management for the signal bus.

  This module contains the subscriber type definition and functions for creating,
  managing, and dispatching signals to subscribers. It supports both regular and
  persistent subscriptions, handling subscription lifetime and signal delivery.
  """

  alias Jido.Signal.Bus.State, as: BusState
  alias Jido.Signal.Bus.Subscriber
  alias Jido.Signal.Error
  alias Jido.Signal.Names
  alias Jido.Signal.Router

  require Logger

  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Zoi.string(),
              path: Zoi.string(),
              dispatch: Zoi.any(),
              persistent?: Zoi.default(Zoi.boolean(), false) |> Zoi.optional(),
              persistence_pid: Zoi.any() |> Zoi.nullable() |> Zoi.optional(),
              disconnected?: Zoi.default(Zoi.boolean(), false) |> Zoi.optional(),
              created_at: Zoi.any() |> Zoi.nullable() |> Zoi.optional()
            }
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for Subscriber"
  def schema, do: @schema

  @spec subscribe(BusState.t(), String.t(), String.t(), keyword()) ::
          {:ok, BusState.t()} | {:error, Exception.t()}
  def subscribe(%BusState{} = state, subscription_id, path, opts) do
    if BusState.has_subscription?(state, subscription_id) do
      {:error,
       Error.validation_error(
         "Subscription already exists",
         %{field: :subscription_id, value: subscription_id}
       )}
    else
      do_subscribe(state, subscription_id, path, opts)
    end
  end

  defp do_subscribe(state, subscription_id, path, opts) do
    persistent? = Keyword.get(opts, :persistent?, false)
    dispatch = Keyword.get(opts, :dispatch)

    subscription = %Subscriber{
      id: subscription_id,
      path: path,
      dispatch: dispatch,
      persistent?: persistent?,
      persistence_pid: nil,
      created_at: DateTime.utc_now()
    }

    if persistent? do
      create_persistent_subscription(state, subscription_id, subscription, opts)
    else
      create_regular_subscription(state, subscription_id, subscription)
    end
  end

  defp create_persistent_subscription(state, subscription_id, subscription, opts) do
    client_pid = extract_client_pid(subscription.dispatch)

    persistent_sub_opts =
      build_persistent_opts(state, subscription_id, subscription, client_pid, opts)

    case start_persistent_child(state, persistent_sub_opts) do
      {:ok, pid} ->
        finalize_persistent_subscription(state, subscription_id, subscription, pid)

      {:error, reason} ->
        {:error,
         Error.execution_error(
           "Failed to start persistent subscription",
           %{action: "start_persistent_subscription", reason: reason}
         )}
    end
  end

  defp build_persistent_opts(state, subscription_id, subscription, client_pid, opts) do
    [
      id: subscription_id,
      bus_pid: self(),
      bus_name: state.name,
      bus_subscription: subscription,
      start_from: opts[:start_from] || :origin,
      max_in_flight: opts[:max_in_flight] || 1000,
      max_pending: opts[:max_pending] || 10_000,
      max_attempts: opts[:max_attempts] || 5,
      retry_interval: opts[:retry_interval] || 100,
      client_pid: client_pid,
      task_supervisor: Names.task_supervisor(jido: state.jido),
      journal_adapter: state.journal_adapter,
      journal_pid: state.journal_pid
    ]
  end

  defp start_persistent_child(state, persistent_sub_opts) do
    DynamicSupervisor.start_child(
      state.child_supervisor,
      {Jido.Signal.Bus.PersistentSubscription, persistent_sub_opts}
    )
  end

  defp finalize_persistent_subscription(state, subscription_id, subscription, pid) do
    subscription = %{subscription | persistence_pid: pid}

    case BusState.add_subscription(state, subscription_id, subscription) do
      {:ok, new_state} ->
        {:ok, new_state}

      {:error, reason} ->
        {:error,
         Error.execution_error(
           "Failed to add subscription",
           %{action: "add_subscription", reason: reason}
         )}
    end
  end

  defp create_regular_subscription(state, subscription_id, subscription) do
    new_state = %{
      state
      | subscriptions: Map.put(state.subscriptions, subscription_id, subscription)
    }

    route = %Router.Route{
      path: subscription.path,
      target: subscription.dispatch,
      priority: 0,
      match: nil
    }

    case BusState.add_route(new_state, route) do
      {:ok, final_state} ->
        {:ok, final_state}

      {:error, reason} ->
        {:error,
         Error.execution_error(
           "Failed to add subscription route",
           %{action: "add_route", reason: reason}
         )}
    end
  end

  @doc """
  Unsubscribes from the bus by removing the subscription and cleaning up resources.

  For persistent subscriptions, this also terminates the associated process.

  ## Parameters

  - `state`: The current bus state
  - `subscription_id`: The unique identifier of the subscription to remove
  - `opts`: Additional options (currently unused)

  ## Returns

  - `{:ok, new_state}` if successful
  - `{:error, Exception.t()}` if the subscription doesn't exist or removal fails
  """
  @spec unsubscribe(BusState.t(), String.t(), keyword()) ::
          {:ok, BusState.t()} | {:error, Exception.t()}
  def unsubscribe(%BusState{} = state, subscription_id, opts \\ []) do
    # Get the subscription before removing it
    subscription = BusState.get_subscription(state, subscription_id)

    case BusState.remove_subscription(state, subscription_id, opts) do
      {:ok, new_state} ->
        maybe_shutdown_persistent_subscription(state, subscription)
        maybe_delete_persistence(state, subscription_id, subscription, opts)

        {:ok, new_state}

      {:error, :subscription_not_found} ->
        {:error,
         Error.validation_error(
           "Subscription does not exist",
           %{field: :subscription_id, value: subscription_id}
         )}
    end
  end

  defp maybe_shutdown_persistent_subscription(state, subscription) do
    if subscription && subscription.persistent? && subscription.persistence_pid do
      try do
        DynamicSupervisor.terminate_child(state.child_supervisor, subscription.persistence_pid)
      catch
        :exit, _reason -> :ok
      end
    end
  end

  defp maybe_delete_persistence(state, subscription_id, subscription, opts) do
    should_delete? = Keyword.get(opts, :delete_persistence, false)

    if ((should_delete? and subscription) && subscription.persistent?) and state.journal_adapter do
      checkpoint_key = "#{state.name}:#{subscription_id}"

      case state.journal_adapter.delete_checkpoint(checkpoint_key, state.journal_pid) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.warning("Failed to delete checkpoint for #{checkpoint_key}: #{inspect(reason)}")
      end

      case state.journal_adapter.clear_dlq(subscription_id, state.journal_pid) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.warning(
            "Failed to clear DLQ for subscription #{subscription_id}: #{inspect(reason)}"
          )
      end
    end
  end

  # Helper function to extract client PID from dispatch configuration
  @spec extract_client_pid(term()) :: pid() | nil
  defp extract_client_pid({:pid, opts}) when is_list(opts) do
    Keyword.get(opts, :target)
  end

  defp extract_client_pid(_) do
    nil
  end
end
