defmodule Jido.Signal.Router.Cache do
  @moduledoc """
  Optional persistent_term caching for Router tries.

  This module provides a caching layer for router tries using Erlang's `:persistent_term`
  storage. This is useful for hot-path routing where you want to avoid the overhead of
  passing the router struct through function calls.

  ## When to Use

  - High-throughput signal routing (10k+ signals/sec)
  - Router configuration that changes infrequently
  - When you need to share a router across processes without passing the struct

  ## When NOT to Use

  - Routers that change frequently (persistent_term has global GC on update)
  - Short-lived routers
  - When you already have the router struct available

  ## Usage

      # Create and cache a router
      {:ok, router} = Router.new([{"user.created", MyHandler}], cache_id: :my_router)

      # Route using the cached trie (avoids struct lookup)
      {:ok, handlers} = Router.Cache.route(:my_router, signal)

      # Manually cache an existing router
      :ok = Router.Cache.put(:my_router, router)

      # Get cached router
      {:ok, router} = Router.Cache.get(:my_router)

      # Delete cached router
      :ok = Router.Cache.delete(:my_router)

  ## Multiple Routers

  Each router is identified by a unique cache_id (atom or tuple). This allows
  multiple routers to coexist in the cache:

      {:ok, router1} = Router.new(routes1, cache_id: :user_router)
      {:ok, router2} = Router.new(routes2, cache_id: :payment_router)

  ## Performance Considerations

  - Reads from persistent_term are extremely fast (no copying)
  - Writes trigger a global garbage collection of all persistent_terms
  - Best for routers that are configured at startup and rarely change
  """

  alias Jido.Signal
  alias Jido.Signal.Error
  alias Jido.Signal.Router.Engine
  alias Jido.Signal.Telemetry

  @type cache_id :: atom() | {atom(), term()}

  @doc """
  Stores a router's trie in persistent_term cache.

  ## Parameters
  - cache_id: Unique identifier for this cached router (atom or tuple)
  - router: The Router struct to cache (or any struct with a `:trie` field)

  ## Returns
  - :ok

  ## Example

      :ok = Router.Cache.put(:my_router, router)
  """
  @spec put(cache_id(), map()) :: :ok
  def put(cache_id, %{trie: trie}) when is_atom(cache_id) or is_tuple(cache_id) do
    :persistent_term.put(cache_key(cache_id), trie)
  end

  @doc """
  Retrieves a cached router trie and wraps it in a Router struct.

  ## Parameters
  - cache_id: The identifier used when caching the router

  ## Returns
  - `{:ok, %Router{}}` if found
  - `{:error, :not_found}` if not cached

  ## Example

      {:ok, router} = Router.Cache.get(:my_router)
  """
  @spec get(cache_id()) :: {:ok, map()} | {:error, :not_found}
  def get(cache_id) when is_atom(cache_id) or is_tuple(cache_id) do
    alias Jido.Signal.Router.Router

    case :persistent_term.get(cache_key(cache_id), :not_found) do
      :not_found ->
        {:error, :not_found}

      trie ->
        route_count = Engine.count_routes(trie)
        {:ok, %Router{trie: trie, route_count: route_count, cache_id: cache_id}}
    end
  end

  @doc """
  Removes a router from the cache.

  ## Parameters
  - cache_id: The identifier used when caching the router

  ## Returns
  - :ok (always succeeds, even if key didn't exist)

  ## Example

      :ok = Router.Cache.delete(:my_router)
  """
  @spec delete(cache_id()) :: :ok
  def delete(cache_id) when is_atom(cache_id) or is_tuple(cache_id) do
    _ = :persistent_term.erase(cache_key(cache_id))
    :ok
  end

  @doc """
  Checks if a router is cached.

  ## Parameters
  - cache_id: The identifier to check

  ## Returns
  - true if cached, false otherwise
  """
  @spec cached?(cache_id()) :: boolean()
  def cached?(cache_id) when is_atom(cache_id) or is_tuple(cache_id) do
    :persistent_term.get(cache_key(cache_id), :not_found) != :not_found
  end

  @doc """
  Routes a signal using a cached router trie directly.

  This is the most efficient way to route signals when the router is cached,
  as it avoids the overhead of reconstructing the Router struct.

  ## Parameters
  - cache_id: The identifier of the cached router
  - signal: The signal to route

  ## Returns
  - `{:ok, [targets]}` - List of matching targets
  - `{:error, :not_cached}` - Router not in cache
  - `{:error, reason}` - Routing error

  ## Example

      {:ok, handlers} = Router.Cache.route(:my_router, signal)
  """
  @spec route(cache_id(), Signal.t()) :: {:ok, [term()]} | {:error, term()}
  def route(cache_id, %Signal{type: nil}) do
    {:error,
     Error.routing_error(
       "Signal type cannot be nil",
       %{route: nil, reason: :nil_signal_type, cache_id: cache_id}
     )}
  end

  def route(cache_id, %Signal{} = signal) when is_atom(cache_id) or is_tuple(cache_id) do
    case :persistent_term.get(cache_key(cache_id), :not_found) do
      :not_found ->
        {:error, :not_cached}

      trie ->
        start_time = System.monotonic_time(:microsecond)
        results = Engine.route_signal(trie, signal)
        latency_us = System.monotonic_time(:microsecond) - start_time

        case results do
          [] ->
            Telemetry.execute(
              [:jido, :signal, :router, :routed],
              %{latency_us: latency_us, match_count: 0},
              %{signal_type: signal.type, cache_id: cache_id, matched: false}
            )

            {:error,
             Error.routing_error(
               "No matching handlers found for signal",
               %{signal_type: signal.type, route: signal.type, reason: :no_handlers_found}
             )}

          _ ->
            Telemetry.execute(
              [:jido, :signal, :router, :routed],
              %{latency_us: latency_us, match_count: length(results)},
              %{signal_type: signal.type, cache_id: cache_id, matched: true}
            )

            {:ok, results}
        end
    end
  end

  @doc """
  Lists all cached router IDs.

  Note: This iterates all persistent_terms, so use sparingly.

  ## Returns
  - List of cache_ids for routers
  """
  @spec list_cached() :: [cache_id()]
  def list_cached do
    :persistent_term.get()
    |> Enum.filter(fn {key, _value} ->
      match?({:jido_signal_router_cache, _}, key)
    end)
    |> Enum.map(fn {{:jido_signal_router_cache, id}, _value} -> id end)
  end

  @doc """
  Updates a cached router with new routes.

  This is a convenience function that:
  1. Gets the cached router (or creates empty)
  2. Adds the new routes
  3. Updates the cache

  ## Parameters
  - cache_id: The identifier of the cached router
  - routes: Routes to add (same format as Router.add/2)

  ## Returns
  - `{:ok, updated_router}` on success
  - `{:error, reason}` on failure
  """
  @spec update(cache_id(), term()) :: {:ok, map()} | {:error, term()}
  def update(cache_id, routes) when is_atom(cache_id) or is_tuple(cache_id) do
    alias Jido.Signal.Router
    alias Jido.Signal.Router.Router, as: RouterStruct

    router =
      case get(cache_id) do
        {:ok, existing} -> existing
        {:error, :not_found} -> %RouterStruct{cache_id: cache_id}
      end

    case Router.add(router, routes) do
      {:ok, updated} ->
        put(cache_id, updated)
        {:ok, updated}

      error ->
        error
    end
  end

  # Private helpers

  defp cache_key(cache_id), do: {:jido_signal_router_cache, cache_id}
end
