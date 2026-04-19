defmodule Jido.Signal.Bus.State do
  @moduledoc """
  Defines the state structure for the signal bus.

  This module contains the type definitions and operations for managing
  the internal state of the signal bus, including signal logs, subscriptions,
  snapshots, and router configuration. It provides functions for manipulating
  and querying this state.
  """

  alias Jido.Signal
  alias Jido.Signal.ID
  alias Jido.Signal.Router
  alias Jido.Signal.Telemetry

  @schema Zoi.struct(
            __MODULE__,
            %{
              name: Zoi.atom(),
              jido: Zoi.atom() |> Zoi.nullable() |> Zoi.optional(),
              router: Zoi.any() |> Zoi.nullable() |> Zoi.optional(),
              log: Zoi.default(Zoi.map(), %{}) |> Zoi.optional(),
              snapshots: Zoi.default(Zoi.map(), %{}) |> Zoi.optional(),
              subscriptions: Zoi.default(Zoi.map(), %{}) |> Zoi.optional(),
              child_supervisor: Zoi.any() |> Zoi.nullable() |> Zoi.optional(),
              middleware: Zoi.default(Zoi.list(), []) |> Zoi.optional(),
              middleware_timeout_ms: Zoi.default(Zoi.integer(), 100) |> Zoi.optional(),
              journal_adapter: Zoi.atom() |> Zoi.nullable() |> Zoi.optional(),
              journal_pid: Zoi.any() |> Zoi.nullable() |> Zoi.optional(),
              journal_owned?: Zoi.default(Zoi.boolean(), false) |> Zoi.optional(),
              partition_count: Zoi.default(Zoi.integer(), 1) |> Zoi.optional(),
              partition_supervisor: Zoi.any() |> Zoi.nullable() |> Zoi.optional(),
              partition_pids: Zoi.default(Zoi.list(), []) |> Zoi.optional(),
              max_log_size: Zoi.default(Zoi.integer(), 100_000) |> Zoi.optional(),
              log_ttl_ms: Zoi.integer() |> Zoi.nullable() |> Zoi.optional(),
              gc_timer_ref: Zoi.any() |> Zoi.nullable() |> Zoi.optional(),
              publish_inflight: Zoi.any() |> Zoi.nullable() |> Zoi.optional(),
              publish_queue: Zoi.default(Zoi.list(), []) |> Zoi.optional()
            }
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for State"
  def schema, do: @schema

  @doc """
  Creates a new BusState with the given name and options.

  Automatically initializes the router to `Router.new!()` if not provided.

  ## Examples

      iex> state = Jido.Signal.Bus.State.new(:my_bus)
      iex> state.name
      :my_bus
  """
  @spec new(atom(), keyword()) :: t()
  def new(name, opts \\ []) do
    router = Keyword.get_lazy(opts, :router, fn -> Router.new!() end)

    %__MODULE__{
      name: name,
      router: router,
      jido: Keyword.get(opts, :jido),
      child_supervisor: Keyword.get(opts, :child_supervisor),
      log: Keyword.get(opts, :log, %{}),
      snapshots: Keyword.get(opts, :snapshots, %{}),
      subscriptions: Keyword.get(opts, :subscriptions, %{}),
      middleware: Keyword.get(opts, :middleware, []),
      middleware_timeout_ms: Keyword.get(opts, :middleware_timeout_ms, 100),
      journal_adapter: Keyword.get(opts, :journal_adapter),
      journal_pid: Keyword.get(opts, :journal_pid),
      journal_owned?: Keyword.get(opts, :journal_owned?, false),
      partition_count: Keyword.get(opts, :partition_count, 1),
      partition_supervisor: Keyword.get(opts, :partition_supervisor),
      partition_pids: Keyword.get(opts, :partition_pids, []),
      max_log_size: Keyword.get(opts, :max_log_size, 100_000),
      log_ttl_ms: Keyword.get(opts, :log_ttl_ms),
      gc_timer_ref: Keyword.get(opts, :gc_timer_ref),
      publish_inflight: Keyword.get(opts, :publish_inflight),
      publish_queue: Keyword.get(opts, :publish_queue, [])
    }
  end

  @doc """
  Merges a list of recorded signals into the existing log.
  Signals are added to the log keyed by their IDs.
  If a signal with the same ID already exists, it will be overwritten.

  ## Parameters
    - state: The current bus state
    - signals: List of recorded signals to merge

  ## Returns
    - `{:ok, new_state, recorded_signals}` with signals merged into log
    - `{:error, reason}` if there was an error processing the signals
  """
  @spec append_signals(t(), [Jido.Signal.t() | {:ok, Jido.Signal.t()} | map()]) ::
          {:ok, t(), [{String.t(), Signal.t()}]} | {:error, term()}
  def append_signals(%__MODULE__{} = state, signals) when is_list(signals) do
    if signals == [] do
      {:ok, state, []}
    else
      try do
        {uuids, _timestamp} = ID.generate_batch(length(signals))
        uuid_signal_pairs = Enum.zip(uuids, signals)

        with {:ok, new_state} <- append_uuid_signal_pairs(state, uuid_signal_pairs) do
          {:ok, new_state, uuid_signal_pairs}
        end
      rescue
        e in KeyError ->
          {:error, "Invalid signal format: #{Exception.message(e)}"}

        e ->
          {:error, "Error processing signals: #{Exception.message(e)}"}
      end
    end
  end

  @doc """
  Appends pre-generated `{log_id, signal}` pairs into the state log.
  """
  @spec append_uuid_signal_pairs(t(), [{String.t(), Signal.t()}]) :: {:ok, t()} | {:error, term()}
  def append_uuid_signal_pairs(%__MODULE__{} = state, uuid_signal_pairs)
      when is_list(uuid_signal_pairs) do
    try do
      new_log =
        Enum.reduce(uuid_signal_pairs, state.log, fn {uuid, signal}, acc ->
          Map.put(acc, uuid, signal)
        end)

      {final_log, truncated_count} =
        if map_size(new_log) > state.max_log_size do
          truncated = truncate_to_size(new_log, state.max_log_size)
          {truncated, map_size(new_log) - state.max_log_size}
        else
          {new_log, 0}
        end

      if truncated_count > 0 do
        Telemetry.execute(
          [:jido, :signal, :bus, :log_truncated],
          %{removed_count: truncated_count},
          %{bus_name: state.name, new_size: state.max_log_size}
        )
      end

      {:ok, %{state | log: final_log}}
    rescue
      e in KeyError ->
        {:error, "Invalid signal format: #{Exception.message(e)}"}

      e ->
        {:error, "Error processing signals: #{Exception.message(e)}"}
    end
  end

  # Truncates log to max_size, keeping the most recent entries (UUID7 is time-ordered)
  defp truncate_to_size(log, max_size) do
    log
    |> Enum.sort_by(fn {key, _signal} -> key end)
    |> Enum.take(-max_size)
    |> Map.new()
  end

  @doc """
  Converts the signal log from a map to a list sorted by recorded log key.

  ## Parameters

  - `state`: The current bus state

  ## Returns

  A list of signals sorted by recorded log key chronology.

  ## Examples

      iex> state = %Jido.Signal.Bus.State{log: %{"2" => signal2, "1" => signal1}}
      iex> signals = Jido.Signal.Bus.State.log_to_list(state)
      iex> length(signals)
      2
      iex> Enum.map(signals, & &1.id)
      ["1", "2"]
  """
  @spec log_to_list(t()) :: list(Signal.t())
  def log_to_list(%__MODULE__{} = state) do
    state
    |> log_entries_to_list()
    |> Enum.map(fn {_log_id, signal} -> signal end)
  end

  @doc """
  Converts the signal log from a map to a list of `{log_id, signal}` tuples
  sorted by recorded log key chronology.
  """
  @spec log_entries_to_list(t()) :: [{String.t(), Signal.t()}]
  def log_entries_to_list(%__MODULE__{} = state) do
    state.log
    |> Enum.sort_by(fn {log_id, _signal} -> log_id end)
  end

  @doc """
  Truncates the signal log to the specified maximum size.
  Keeps the most recent signals and discards older ones.
  """
  @spec truncate_log(t(), non_neg_integer()) :: {:ok, t()}
  def truncate_log(%__MODULE__{} = state, max_size) when is_integer(max_size) and max_size >= 0 do
    if map_size(state.log) <= max_size do
      # No truncation needed
      {:ok, state}
    else
      sorted_entries = log_entries_to_list(state)

      # Keep only the most recent max_size signals
      to_keep = Enum.take(sorted_entries, -max_size)

      truncated_log = Map.new(to_keep)

      {:ok, %{state | log: truncated_log}}
    end
  end

  @doc """
  Clears all signals from the log.
  """
  @spec clear_log(t()) :: {:ok, t()}
  def clear_log(%__MODULE__{} = state) do
    {:ok, %{state | log: %{}}}
  end

  @doc """
  Adds a route to the router in the bus state.

  ## Parameters

  - `state`: The current bus state
  - `route`: The route to add to the router

  ## Returns

  - `{:ok, new_state}` if successful
  - `{:error, reason}` if the route addition fails
  """
  @spec add_route(t(), Router.Route.t()) :: {:ok, t()} | {:error, term()}
  def add_route(%__MODULE__{} = state, route) do
    case Router.add(state.router, route) do
      {:ok, new_router} -> {:ok, %{state | router: new_router}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Removes a route from the router in the bus state.

  ## Parameters

  - `state`: The current bus state
  - `route`: The route to remove (can be a Route struct or path string)

  ## Returns

  - `{:ok, new_state}` if successful
  - `{:error, :route_not_found}` if the route doesn't exist
  """
  @spec remove_route(t(), Router.Route.t() | String.t()) ::
          {:ok, t()} | {:error, :route_not_found}
  def remove_route(%__MODULE__{} = state, %Router.Route{} = route) do
    # Extract the path from the route
    path = route.path

    # Check if the route exists before trying to remove it
    {:ok, routes} = Router.list(state.router)
    route_exists = Enum.any?(routes, fn r -> r.path == path end)

    if route_exists do
      {:ok, new_router} = Router.remove(state.router, path)
      {:ok, %{state | router: new_router}}
    else
      {:error, :route_not_found}
    end
  end

  def remove_route(%__MODULE__{} = state, path) when is_binary(path) do
    # Check if the route exists before trying to remove it
    {:ok, routes} = Router.list(state.router)
    route_exists = Enum.any?(routes, fn r -> r.path == path end)

    if route_exists do
      {:ok, new_router} = Router.remove(state.router, path)
      {:ok, %{state | router: new_router}}
    else
      {:error, :route_not_found}
    end
  end

  @doc """
  Checks if a subscription exists in the bus state.

  ## Parameters

  - `state`: The current bus state
  - `subscription_id`: The ID of the subscription to check

  ## Returns

  `true` if the subscription exists, `false` otherwise
  """
  @spec has_subscription?(t(), String.t()) :: boolean()
  def has_subscription?(%__MODULE__{} = state, subscription_id) do
    Map.has_key?(state.subscriptions, subscription_id)
  end

  @doc """
  Retrieves a subscription from the bus state.

  ## Parameters

  - `state`: The current bus state
  - `subscription_id`: The ID of the subscription to retrieve

  ## Returns

  The subscription struct if found, `nil` otherwise
  """
  @spec get_subscription(t(), String.t()) :: Jido.Signal.Bus.Subscriber.t() | nil
  def get_subscription(%__MODULE__{} = state, subscription_id) do
    Map.get(state.subscriptions, subscription_id)
  end

  @doc """
  Adds a subscription to the bus state and creates a corresponding route.

  ## Parameters

  - `state`: The current bus state
  - `subscription_id`: The unique ID for the subscription
  - `subscription`: The subscription struct to add

  ## Returns

  - `{:ok, new_state}` if successful
  - `{:error, :subscription_exists}` if a subscription with this ID already exists
  """
  @spec add_subscription(t(), String.t(), Jido.Signal.Bus.Subscriber.t()) ::
          {:ok, t()} | {:error, atom()}
  def add_subscription(%__MODULE__{} = state, subscription_id, subscription) do
    if has_subscription?(state, subscription_id) do
      {:error, :subscription_exists}
    else
      new_state = %{
        state
        | subscriptions: Map.put(state.subscriptions, subscription_id, subscription)
      }

      add_route(new_state, subscription_to_route(subscription))
    end
  end

  @doc """
  Removes a subscription from the bus state and its corresponding route.

  ## Parameters

  - `state`: The current bus state
  - `subscription_id`: The ID of the subscription to remove
  - `opts`: Options including:
    - `:delete_persistence` - Whether to delete persistence artifacts (default: false)

  ## Returns

  - `{:ok, new_state}` if successful
  - `{:error, :subscription_not_found}` if the subscription doesn't exist
  """
  @spec remove_subscription(t(), String.t(), keyword()) :: {:ok, t()} | {:error, atom()}
  def remove_subscription(%__MODULE__{} = state, subscription_id, opts \\ []) do
    _delete_persistence = Keyword.get(opts, :delete_persistence, false)

    if has_subscription?(state, subscription_id) do
      {subscription, new_subscriptions} = Map.pop(state.subscriptions, subscription_id)
      new_state = %{state | subscriptions: new_subscriptions}

      {:ok, new_router} = Router.remove(new_state.router, subscription.path)
      {:ok, %{new_state | router: new_router}}
    else
      {:error, :subscription_not_found}
    end
  end

  @spec subscription_to_route(Jido.Signal.Bus.Subscriber.t()) :: Router.Route.t()
  defp subscription_to_route(subscription) do
    %Router.Route{
      # Use the path pattern for matching
      path: subscription.path,
      target: subscription.dispatch,
      priority: 0,
      # Let the Router's path matching handle wildcards
      match: nil
    }
  end
end
