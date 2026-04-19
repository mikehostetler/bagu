defmodule Jido.Signal.Router do
  @moduledoc """
  The Router module implements a high-performance, trie-based signal routing system designed specifically for agent-based architectures. It provides sophisticated message routing capabilities with support for exact matches, wildcards, pattern matching functions, and multiple dispatch targets.

  ## Core Concepts

  The Router organizes signal handlers into an efficient trie (prefix tree) structure that enables:
  - Fast path-based routing using dot-notation (e.g., "user.created.verified")
  - Priority-based handler execution (-100 to 100)
  - Complexity-based ordering for wildcard resolution
  - Dynamic route management (add/remove at runtime)
  - Pattern matching through custom functions
  - Multiple dispatch targets per route

  ### Path Patterns

  Routes use a dot-notation pattern system supporting:
  - Exact matches: `"user.created"`
  - Single wildcards: `"user.*.updated"` (matches one segment)
  - Multi-level wildcards: `"audit.**"` (matches zero or more segments)

  Pattern rules:
  - Paths must match: `^[a-zA-Z0-9.*_-]+(\.[a-zA-Z0-9.*_-]+)*$`
  - Cannot contain consecutive dots (..)
  - Cannot contain consecutive multi-wildcards (`**...**`)

  ### Handler Priority

  Handlers execute in order based on:
  1. Path complexity (more specific paths execute first)
  2. Priority (-100 to 100, higher executes first)
  3. Registration order (for equal priority/complexity)

  ### Target Types

  The router accepts any term as a target. Common patterns include:
  1. Atoms - Simple handler references
  2. Tuples - Configuration with options `{handler, opts}`
  3. Lists - Multiple targets `[{handler1, opts1}, {handler2, opts2}]`
  4. Any other term - Custom data structures

  ## Usage Examples

  Basic route creation:
  ```elixir
  {:ok, router} = Router.new([
    # Simple route with default priority
    {"user.created", HandleUserCreated},

    # High-priority audit logging
    {"audit.**", AuditLogger, 100},

    # Pattern matching for large payments
    {"payment.processed",
      fn signal -> signal.data.amount > 1000 end,
      HandleLargePayment},

    # Single dispatch target
    {"metrics.collected", {MetricsAdapter, [type: :counter]}},

    # Multiple dispatch targets
    {"system.error", [
      {MetricsAdapter, [type: :error]},
      {AlertAdapter, [priority: :high]},
      {LogAdapter, [level: :error]}
    ]}
  ])
  ```

  Dynamic route management:
  ```elixir
  # Add routes
  {:ok, router} = Router.add(router, [
    {"metrics.**", {MetricsAdapter, [type: :gauge]}}
  ])

  # Remove routes
  {:ok, router} = Router.remove(router, "metrics.**")
  ```

  Signal routing:
  ```elixir
  # Route to handler
  {:ok, [HandleUserCreated]} = Router.route(router, Jido.Signal.new!("user.created", %{id: "123"}))

  # Route to multiple dispatch targets
  {:ok, [
    {MetricsAdapter, [type: :error]},
    {AlertAdapter, [priority: :high]},
    {LogAdapter, [level: :error]}
  ]} = Router.route(router, Jido.Signal.new!("system.error", %{message: "Critical error"}))
  ```

  ## Path Complexity Scoring

  The router uses a sophisticated scoring system to determine handler execution order:

  1. Base score from segment count (length * 2000)
  2. Exact match bonuses (3000 per segment, weighted by position)
  3. Wildcard penalties:
     - Single wildcard (*): 1000 - position_index * 100
     - Multi-wildcard (**): 2000 - position_index * 200

  This ensures more specific routes take precedence over wildcards, while maintaining predictable execution order.

  ## Best Practices

  1. Route Design
     - Use consistent, hierarchical path patterns
     - Prefer exact matches over wildcards when possible
     - Keep path segments meaningful and well-structured
     - Document your path hierarchy

  2. Priority Management
     - Reserve high priorities (75-100) for critical handlers
     - Use default priority (0) for standard business logic
     - Reserve low priorities (-100 to -75) for metrics/logging
     - Document priority ranges for your application

  3. Pattern Matching
     - Keep match functions simple and fast
     - Handle nil/missing data gracefully
     - Avoid side effects in match functions
     - Test edge cases thoroughly

  4. Dispatch Configuration
     - Use single dispatch for simple routing
     - Use multiple dispatch for cross-cutting concerns
     - Keep adapter options minimal and focused
     - Document adapter requirements

  5. Performance Considerations
     - Monitor route count in production
     - Use pattern matching sparingly
     - Consider complexity scores when designing paths
     - Profile routing performance under load

  ## Error Handling

  The router provides detailed error feedback for:
  - Invalid path patterns
  - Priority out of bounds
  - Invalid match functions
  - Missing handlers
  - Malformed signals
  - Invalid dispatch configurations

  ## Implementation Details

  The router uses several specialized structs:
  - `Route` - Defines a single routing rule
  - `TrieNode` - Internal trie structure node
  - `HandlerInfo` - Stores handler metadata
  - `PatternMatch` - Encapsulates pattern matching rules

  See the corresponding typespecs for detailed field information.

  ## See Also

  - `Jido.Signal` - Signal structure and validation
  - `Jido.Signal.Errors` - Error types and handling
  - `Jido.Signal.Dispatch` - Dispatch adapter interface
  """
  alias Jido.Signal
  alias Jido.Signal.Error
  alias Jido.Signal.Router.{Cache, Engine, Route, Validator}
  alias Jido.Signal.Telemetry

  @type cache_id :: Cache.cache_id()

  @type t :: %{
          trie: __MODULE__.TrieNode.t(),
          route_count: non_neg_integer(),
          cache_id: cache_id() | nil
        }

  @type path :: String.t()
  @type match :: (Signal.t() -> boolean())
  @type priority :: non_neg_integer()
  @type wildcard_type :: :single | :multi
  @type target :: term()

  @type route_spec ::
          {String.t(), target()}
          | {String.t(), target(), priority()}
          | {String.t(), match(), target()}
          | {String.t(), match(), target(), priority()}

  @doc """
  Normalizes route specifications into Route structs.

  ## Parameters
  * `input` - One of:
    * Single Route struct
    * List of Route structs
    * List of route_spec tuples:
      * {path, target} tuple where target can be any term
      * {path, target, priority} tuple
      * {path, match_fn, target} tuple
      * {path, match_fn, target, priority} tuple
  ## Returns
    * `{:ok, [%Route{}]}` - List of normalized Route structs
    * `{:error, term()}` - If normalization fails
  """
  @spec normalize(Route.t() | [Route.t()] | route_spec() | [route_spec()]) ::
          {:ok, [Route.t()]} | {:error, term()}
  defdelegate normalize(input), to: Validator

  defmodule HandlerInfo do
    @moduledoc "Router Helper struct to store handler metadata"

    @schema Zoi.struct(
              __MODULE__,
              %{
                target: Zoi.any(),
                priority: Zoi.default(Zoi.integer(), 0) |> Zoi.optional(),
                complexity: Zoi.default(Zoi.integer(), 0) |> Zoi.optional()
              }
            )

    @type t :: unquote(Zoi.type_spec(@schema))
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @doc "Returns the Zoi schema for HandlerInfo"
    def schema, do: @schema
  end

  defmodule PatternMatch do
    @moduledoc "Router Helper struct to store pattern match metadata"

    @schema Zoi.struct(
              __MODULE__,
              %{
                match: Zoi.any(),
                target: Zoi.any(),
                priority: Zoi.default(Zoi.integer(), 0) |> Zoi.optional(),
                complexity: Zoi.default(Zoi.integer(), 0) |> Zoi.optional()
              }
            )

    @type t :: unquote(Zoi.type_spec(@schema))
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @doc "Returns the Zoi schema for PatternMatch"
    def schema, do: @schema
  end

  defmodule NodeHandlers do
    @moduledoc "Router Helper struct to store node handler metadata"

    @schema Zoi.struct(
              __MODULE__,
              %{
                handlers: Zoi.default(Zoi.list(), []) |> Zoi.optional(),
                matchers: Zoi.default(Zoi.list(), []) |> Zoi.optional()
              }
            )

    @type t :: unquote(Zoi.type_spec(@schema))
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @doc "Returns the Zoi schema for NodeHandlers"
    def schema, do: @schema
  end

  defmodule WildcardHandlers do
    @moduledoc "Router Helper struct to store wildcard handler metadata"

    @schema Zoi.struct(
              __MODULE__,
              %{
                type: Zoi.atom(),
                handlers: Zoi.any()
              }
            )

    @type t :: unquote(Zoi.type_spec(@schema))
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @doc "Returns the Zoi schema for WildcardHandlers"
    def schema, do: @schema
  end

  defmodule TrieNode do
    @moduledoc "Router Helper struct to store trie node metadata"

    @schema Zoi.struct(
              __MODULE__,
              %{
                segments: Zoi.default(Zoi.map(), %{}) |> Zoi.optional(),
                wildcards: Zoi.default(Zoi.list(), []) |> Zoi.optional(),
                handlers: Zoi.default(Zoi.any(), %NodeHandlers{}) |> Zoi.optional()
              }
            )

    @type t :: unquote(Zoi.type_spec(@schema))
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @doc "Returns the Zoi schema for TrieNode"
    def schema, do: @schema
  end

  defmodule Route do
    @moduledoc "Router Helper struct to store route metadata"

    @schema Zoi.struct(
              __MODULE__,
              %{
                path: Zoi.string(),
                target: Zoi.any(),
                priority: Zoi.default(Zoi.integer(), 0) |> Zoi.optional(),
                match: Zoi.any() |> Zoi.nullable() |> Zoi.optional()
              }
            )

    @type t :: unquote(Zoi.type_spec(@schema))
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @doc "Returns the Zoi schema for Route"
    def schema, do: @schema
  end

  defmodule Router do
    @moduledoc "Router Helper struct to store router metadata"

    @schema Zoi.struct(
              __MODULE__,
              %{
                trie: Zoi.default(Zoi.any(), %TrieNode{}) |> Zoi.optional(),
                route_count: Zoi.default(Zoi.integer(), 0) |> Zoi.optional(),
                cache_id: Zoi.any() |> Zoi.nullable() |> Zoi.optional()
              }
            )

    @type t :: unquote(Zoi.type_spec(@schema))
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @doc "Returns the Zoi schema for Router"
    def schema, do: @schema
  end

  @type new_opts :: [cache_id: cache_id()]

  @doc """
  Creates a new router with the given routes.

  ## Options
  - `:cache_id` - Optional. When provided, the router's trie is cached in
    `:persistent_term` for fast lookups. Use `Router.Cache.route/2` for
    cached routing.

  ## Examples

      # Without caching (default behavior)
      {:ok, router} = Router.new([{"user.created", MyHandler}])

      # With caching for high-throughput scenarios
      {:ok, router} = Router.new([{"user.created", MyHandler}], cache_id: :user_router)

      # Later, route using the cache directly
      {:ok, handlers} = Router.Cache.route(:user_router, signal)
  """
  @spec new(route_spec() | [route_spec()] | [Route.t()] | nil, new_opts()) ::
          {:ok, Router.t()} | {:error, term()}
  def new(routes \\ nil, opts \\ [])

  def new(nil, opts) do
    cache_id = Keyword.get(opts, :cache_id)
    router = %Router{cache_id: cache_id}

    if cache_id do
      Cache.put(cache_id, router)
    end

    {:ok, router}
  end

  def new(routes, opts) do
    cache_id = Keyword.get(opts, :cache_id)

    with {:ok, normalized} <- Validator.normalize(routes),
         {:ok, validated} <- validate(normalized) do
      trie = Engine.build_trie(validated)
      route_count = count_targets(validated)
      router = %Router{trie: trie, route_count: route_count, cache_id: cache_id}

      if cache_id do
        Cache.put(cache_id, router)
      end

      {:ok, router}
    end
  end

  @doc """
  Creates a new router with the given routes, raising on error.

  See `new/2` for options.
  """
  @spec new!(route_spec() | [route_spec()] | [Route.t()] | nil, new_opts()) :: Router.t()
  def new!(routes \\ nil, opts \\ []) do
    case new(routes, opts) do
      {:ok, router} ->
        router

      {:error, reason} ->
        raise Error.validation_error(
                "Invalid router configuration",
                %{field: "routes", value: routes, reason: reason}
              )
    end
  end

  @doc """
  Adds one or more routes to the router.

  ## Parameters
  - router: The existing router struct
  - routes: A route specification or list of route specifications in one of these formats:
    - %Route{}
    - {path, target}
    - {path, target, priority}
    - {path, match_fn, target}
    - {path, match_fn, target, priority}

  ## Returns
  `{:ok, updated_router}` or `{:error, reason}`
  """
  @spec add(Router.t(), route_spec() | Route.t() | [route_spec()] | [Route.t()]) ::
          {:ok, Router.t()} | {:error, term()}
  def add(%Router{} = router, routes) when is_list(routes) do
    with {:ok, normalized} <- Validator.normalize(routes),
         {:ok, validated} <- validate(normalized) do
      new_trie = Engine.build_trie(validated, router.trie)
      added_count = count_targets(validated)
      updated_router = %{router | trie: new_trie, route_count: router.route_count + added_count}

      if router.cache_id do
        Cache.put(router.cache_id, updated_router)
      end

      {:ok, updated_router}
    end
  end

  def add(%Router{} = router, route) do
    add(router, [route])
  end

  @doc """
  Removes one or more routes from the router.

  ## Parameters
  - router: The Router struct to modify
  - paths: A path string or list of path strings to remove

  ## Returns
  - `{:ok, updated_router}` - Routes removed successfully

  ## Examples

      {:ok, router} = Router.remove(router, "metrics.collected")
      {:ok, router} = Router.remove(router, ["user.created", "user.updated"])
  """
  @spec remove(Router.t(), String.t() | [String.t()]) :: {:ok, Router.t()}
  def remove(%Router{} = router, paths) when is_list(paths) do
    {new_trie, total_removed} =
      Enum.reduce(paths, {router.trie, 0}, fn path, {trie, count} ->
        {updated_trie, removed} = Engine.remove_path(path, trie)
        {updated_trie, count + removed}
      end)

    route_count = max(router.route_count - total_removed, 0)
    updated_router = %{router | trie: new_trie, route_count: route_count}

    if router.cache_id do
      Cache.put(router.cache_id, updated_router)
    end

    {:ok, updated_router}
  end

  def remove(%Router{} = router, path) when is_binary(path) do
    remove(router, [path])
  end

  @doc """
  Merges two routers by combining their routes.

  Takes a target router and a list of routes from another router (obtained via `list/1`) and
  merges them together, preserving priorities and match functions.

  ## Parameters
  - router: The target Router struct to merge into
  - routes: List of Route structs to merge in (from Router.list/1)

  ## Returns
  `{:ok, merged_router}` or `{:error, reason}`

  ## Examples

      {:ok, router1} = Router.new([{"user.created", target1}])
      {:ok, router2} = Router.new([{"payment.processed", target2}])
      {:ok, routes2} = Router.list(router2)

      # Merge router2's routes into router1
      {:ok, merged} = Router.merge(router1, routes2)
  """
  @spec merge(Router.t(), [Route.t()]) :: {:ok, Router.t()} | {:error, term()}
  def merge(%Router{} = router, routes) when is_list(routes) do
    # Convert Route structs back to route specs for add/2
    route_specs =
      Enum.map(routes, fn route ->
        case route.match do
          nil ->
            {route.path, route.target, route.priority}

          match_fn when is_function(match_fn) ->
            {route.path, match_fn, route.target, route.priority}
        end
      end)

    add(router, route_specs)
  end

  def merge(%Router{} = router, %Router{} = other) do
    with {:ok, routes} <- list(other) do
      merge(router, routes)
    end
  end

  def merge(%Router{} = _router, invalid) do
    {:error, {:invalid_routes, invalid}}
  end

  @doc """
  Lists all routes currently registered in the router.

  Returns a list of Route structs containing the path, target, priority and match function
  for each registered route.

  ## Returns
  `{:ok, [%Route{}]}` - List of Route structs

  ## Examples

      {:ok, routes} = Router.list(router)

      # Returns:
      [
        %Route{
          path: "user.created",
          target: MyApp.Actions.HandleUserCreated,
          priority: 0,
          match: nil
        },
        %Route{
          path: "payment.processed",
          target: {:some_adapter, [opts: :here]},
          priority: 90,
          match: #Function<1.123456789/1>
        }
      ]
  """
  @spec list(Router.t()) :: {:ok, [Route.t()]}
  def list(%Router{} = router) do
    routes = Engine.collect_routes(router.trie)
    {:ok, routes}
  end

  @doc """
  Validates one or more Route structs.

  ## Parameters
  - routes: A %Route{} struct or list of %Route{} structs to validate

  ## Returns

  * `{:ok, %Route{}}` - Single validated Route struct
  * `{:ok, [%Route{}]}` - List of validated Route structs
  * `{:error, term()}` - If validation fails
  """
  @spec validate(Route.t() | [Route.t()]) :: {:ok, Route.t() | [Route.t()]} | {:error, term()}
  def validate(%Route{} = route) do
    with {:ok, path} <- Validator.validate_path(route.path),
         {:ok, target} <- Validator.validate_target(route.target),
         {:ok, match} <- Validator.validate_match(route.match),
         {:ok, priority} <- Validator.validate_priority(route.priority) do
      {:ok,
       %Route{
         path: path,
         target: target,
         match: match,
         priority: priority
       }}
    end
  end

  def validate(routes) when is_list(routes) do
    routes
    |> Enum.reduce_while({:ok, []}, fn
      %Route{} = route, {:ok, acc} ->
        case validate(route) do
          {:ok, validated} -> {:cont, {:ok, [validated | acc]}}
          error -> {:halt, error}
        end

      invalid, {:ok, _acc} ->
        {:halt,
         {:error,
          Error.validation_error(
            "Expected Route struct",
            %{field: "route", value: invalid}
          )}}
    end)
    |> case do
      {:ok, list} -> {:ok, Enum.reverse(list)}
      error -> error
    end
  end

  def validate(invalid) do
    {:error,
     Error.validation_error(
       "Expected Route struct or list of Route structs",
       %{field: "routes", value: invalid}
     )}
  end

  @doc """
  Routes a signal through the router to find and execute matching handlers.

  ## Parameters
  - router: The router struct to use for routing
  - signal: The signal to route

  ## Returns

  * `{:ok, [term()]}` - List of matching targets, may be empty if no matches
  * `{:error, term()}` - Other errors that occurred during routing

  ## Examples

      {:ok, targets} = Router.route(router, %Signal{
        type: "payment.processed",
        data: %{amount: 100}
      })
  """
  @spec route(Router.t(), Signal.t()) :: {:ok, [term()]} | {:error, term()}
  def route(%Router{trie: _trie}, %Signal{type: nil}) do
    {:error,
     Error.routing_error(
       "Signal type cannot be nil",
       %{route: nil, reason: :nil_signal_type}
     )}
  end

  def route(%Router{trie: trie, cache_id: cache_id}, %Signal{} = signal) do
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

  @doc """
  Checks if a signal type matches a pattern.

  ## Parameters
  - type: The signal type to check (e.g. "user.created")
  - pattern: The pattern to match against (e.g. "user.*" or "audit.**")

  ## Returns
  - `true` if the type matches the pattern
  - `false` otherwise

  ## Examples

      iex> Router.matches?("user.created", "user.*")
      true

      iex> Router.matches?("audit.user.created", "audit.**")
      true

      iex> Router.matches?("user.created", "payment.*")
      false

      iex> Router.matches?("user.profile.updated", "user.*")
      false

      iex> Router.matches?(nil, "user.*")
      false

      iex> Router.matches?("user.created", nil)
      false
  """
  @spec matches?(String.t() | nil | any(), String.t() | nil | any()) :: boolean()
  def matches?(nil, _pattern), do: false
  def matches?(_type, nil), do: false
  def matches?(type, pattern) when not is_binary(type) or not is_binary(pattern), do: false

  def matches?(type, pattern) when is_binary(type) and is_binary(pattern) do
    cond do
      single_wildcard_pattern?(pattern) ->
        match_single_wildcard(type, pattern)

      String.ends_with?(pattern, ".**") ->
        match_multi_wildcard_suffix(type, pattern)

      true ->
        do_matches?(type, pattern)
    end
  end

  # Checks if pattern contains single wildcard but not double wildcard
  defp single_wildcard_pattern?(pattern) do
    String.contains?(pattern, "*") and not String.contains?(pattern, "**")
  end

  # Matches single wildcard patterns (requires exact segment count)
  defp match_single_wildcard(type, pattern) do
    pattern_segments = String.split(pattern, ".")
    type_segments = String.split(type, ".")

    if length(pattern_segments) == length(type_segments) do
      do_matches?(type, pattern)
    else
      false
    end
  end

  # Matches multi-level wildcard suffix patterns (e.g., "foo.**")
  defp match_multi_wildcard_suffix(type, pattern) do
    pattern_base = String.replace_trailing(pattern, ".**", "")

    if String.starts_with?(type, pattern_base) do
      remaining = String.replace_prefix(type, pattern_base, "")
      remaining == "" or String.starts_with?(remaining, ".")
    else
      false
    end
  end

  # Fast segment-based pattern matching (no trie build required)
  @spec match_segments?(String.t(), String.t()) :: boolean()
  defp match_segments?(type, pattern) do
    type_segments = String.split(type, ".")
    pattern_segments = String.split(pattern, ".")

    do_match_segments(type_segments, pattern_segments, 0, 0, nil, nil)
  end

  # Two-pointer matcher with backtracking for **
  # Algorithm: https://leetcode.com/problems/wildcard-matching/
  @spec do_match_segments(
          [String.t()],
          [String.t()],
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer() | nil,
          non_neg_integer() | nil
        ) :: boolean()
  defp do_match_segments(type_segs, pattern_segs, i, j, star_i, star_j) do
    type_len = length(type_segs)
    pattern_len = length(pattern_segs)

    match_state = classify_match_state(type_segs, pattern_segs, i, j, type_len, pattern_len)
    handle_match_state(match_state, type_segs, pattern_segs, i, j, star_i, star_j)
  end

  # Classifies the current match state
  defp classify_match_state(type_segs, pattern_segs, i, j, type_len, pattern_len) do
    cond do
      i >= type_len and j >= pattern_len -> :both_exhausted
      i >= type_len -> :type_exhausted
      j < pattern_len and Enum.at(pattern_segs, j) == "**" -> :double_wildcard
      j < pattern_len and segment_matches?(pattern_segs, type_segs, j, i) -> :segment_match
      true -> :mismatch
    end
  end

  # Checks if pattern segment matches type segment (single wildcard or exact match)
  defp segment_matches?(pattern_segs, type_segs, j, i) do
    pattern_seg = Enum.at(pattern_segs, j)
    pattern_seg == "*" or pattern_seg == Enum.at(type_segs, i)
  end

  # Handles each classified match state
  defp handle_match_state(:both_exhausted, _type_segs, _pattern_segs, _i, _j, _star_i, _star_j) do
    true
  end

  defp handle_match_state(:type_exhausted, _type_segs, pattern_segs, _i, j, _star_i, _star_j) do
    # Check if remaining pattern is all **
    Enum.drop(pattern_segs, j) |> Enum.all?(&(&1 == "**"))
  end

  defp handle_match_state(:double_wildcard, type_segs, pattern_segs, i, j, _star_i, _star_j) do
    # Record backtrack position and advance pattern pointer
    do_match_segments(type_segs, pattern_segs, i, j + 1, i, j + 1)
  end

  defp handle_match_state(:segment_match, type_segs, pattern_segs, i, j, star_i, star_j) do
    # Advance both pointers
    do_match_segments(type_segs, pattern_segs, i + 1, j + 1, star_i, star_j)
  end

  defp handle_match_state(:mismatch, type_segs, pattern_segs, _i, _j, star_i, star_j) do
    # Backtrack to last ** if available
    if star_j == nil do
      false
    else
      do_match_segments(type_segs, pattern_segs, star_i + 1, star_j, star_i + 1, star_j)
    end
  end

  # Direct segment matching - replaces trie-based approach
  defp do_matches?(type, pattern) do
    case Validator.validate_path(pattern) do
      {:ok, _} -> match_segments?(type, pattern)
      {:error, _} -> false
    end
  end

  @doc """
  Filters a list of signals based on a pattern.

  ## Parameters
  - signals: List of signals to filter
  - pattern: Pattern to filter by (e.g. "user.*" or "audit.**")

  ## Returns
  - List of signals whose types match the pattern

  ## Examples

      iex> signals = [
      ...>   %Signal{type: "user.created"},
      ...>   %Signal{type: "payment.processed"},
      ...>   %Signal{type: "user.updated"}
      ...> ]
      iex> Router.filter(signals, "user.*")
      [%Signal{type: "user.created"}, %Signal{type: "user.updated"}]

      iex> Router.filter(nil, "user.*")
      []

      iex> Router.filter([], nil)
      []

      iex> Router.filter("not a list", "user.*")
      []
  """
  @spec filter([Signal.t()] | nil | any(), String.t() | nil | any()) :: [Signal.t()]
  def filter(nil, _pattern), do: []
  def filter(_signals, nil), do: []
  def filter(signals, _pattern) when not is_list(signals), do: []
  def filter(_signals, pattern) when not is_binary(pattern), do: []

  def filter(signals, pattern) when is_list(signals) and is_binary(pattern) do
    case Validator.validate_path(pattern) do
      {:ok, _} ->
        Enum.filter(signals, fn signal ->
          matches?(signal.type, pattern)
        end)

      {:error, _} ->
        []
    end
  end

  @doc """
  Checks if a route with the given ID exists in the router.

  ## Parameters
  - router: The router struct to check
  - route_id: The ID of the route to check for

  ## Returns
  - `true` if the route exists
  - `false` otherwise
  """
  @spec has_route?(Router.t(), String.t()) :: boolean()
  def has_route?(%Router{} = router, path) when is_binary(path) do
    case Validator.validate_path(path) do
      {:ok, _} ->
        segments = String.split(path, ".")
        Engine.has_path?(router.trie, segments)

      {:error, _} ->
        false
    end
  end

  def has_route?(_router, _route_id), do: false

  # Counts targets in a list of routes (multi-target routes count as multiple)
  defp count_targets(routes) do
    Enum.reduce(routes, 0, fn route, acc ->
      acc + target_count(route.target)
    end)
  end

  defp target_count(targets) when is_list(targets), do: length(targets)
  defp target_count(_single_target), do: 1
end
