defmodule Jido.Signal.Router.Engine do
  @moduledoc """
  The routing engine that matches signals to handlers.
  """

  alias Jido.Signal

  alias Jido.Signal.Router.{
    HandlerInfo,
    NodeHandlers,
    PatternMatch,
    Route,
    TrieNode
  }

  @doc """
  Builds the trie structure from validated routes.
  """
  @spec build_trie([Route.t()], TrieNode.t()) :: TrieNode.t()
  def build_trie(routes, base_trie \\ %TrieNode{}) do
    # Precompute segments to avoid repeated splits
    routes_with_segments =
      Enum.map(routes, fn route ->
        segments = route.path |> sanitize_path() |> String.split(".")
        {route, segments}
      end)

    Enum.reduce(routes_with_segments, base_trie, fn {route, segments}, trie ->
      case route.match do
        nil ->
          handler_info = %HandlerInfo{
            target: route.target,
            priority: route.priority,
            complexity: calculate_complexity(route.path)
          }

          do_add_path_route(segments, trie, handler_info)

        match_fn ->
          pattern_match = %PatternMatch{
            match: match_fn,
            target: route.target,
            priority: route.priority,
            complexity: calculate_complexity(route.path)
          }

          do_add_pattern_route(segments, trie, pattern_match)
      end
    end)
  end

  @doc """
  Routes a signal through the trie to find matching handlers.
  """
  @spec route_signal(TrieNode.t(), Signal.t()) :: [term()]
  def route_signal(%TrieNode{} = trie, %Signal{type: type} = signal) when not is_nil(type) do
    segments = String.split(type, ".")
    results = do_route(segments, trie, signal, [])
    Enum.map(results, fn {target, _priority, _complexity} -> target end)
  end

  @doc """
  Removes a path from the trie and returns the number of handlers removed.
  """
  @spec remove_path(String.t(), TrieNode.t()) :: {TrieNode.t(), non_neg_integer()}
  def remove_path(path, trie) do
    segments = path |> sanitize_path() |> String.split(".")
    do_remove_path(segments, trie)
  end

  @doc """
  Counts total routes in the trie.
  """
  @spec count_routes(TrieNode.t()) :: non_neg_integer()
  def count_routes(%TrieNode{segments: segments, handlers: handlers}) do
    handler_count =
      case handlers do
        %NodeHandlers{handlers: handlers, matchers: matchers} ->
          h_count = if is_list(handlers), do: length(handlers), else: 0
          m_count = if is_list(matchers), do: length(matchers), else: 0
          h_count + m_count

        _ ->
          0
      end

    Enum.reduce(segments, handler_count, fn {_segment, node}, acc ->
      acc + count_routes(node)
    end)
  end

  @doc """
  Checks if handlers exist at the exact path in the trie.
  """
  @spec has_path?(TrieNode.t(), [String.t()]) :: boolean()
  def has_path?(trie, segments) do
    do_has_path?(trie, segments)
  end

  @doc """
  Collects all routes from the trie into a list of Route structs.
  """
  @spec collect_routes(TrieNode.t()) :: [Route.t()]
  def collect_routes(%TrieNode{} = trie) do
    collect_routes(trie, [], "")
  end

  # Private helpers

  # Check if handlers exist at exact path
  @spec do_has_path?(TrieNode.t(), [String.t()]) :: boolean()
  defp do_has_path?(%TrieNode{handlers: nil}, []) do
    # At leaf but no handlers exist
    false
  end

  defp do_has_path?(
         %TrieNode{handlers: %NodeHandlers{handlers: handlers, matchers: matchers}},
         []
       ) do
    # At leaf - check if any handlers exist at this exact path
    not Enum.empty?(handlers || []) or not Enum.empty?(matchers || [])
  end

  defp do_has_path?(%TrieNode{} = node, [segment | rest]) do
    case Map.get(node.segments, segment) do
      nil -> false
      child_node -> do_has_path?(child_node, rest)
    end
  end

  defp sanitize_path(path) do
    path
    |> String.trim()
    |> String.replace(~r/\.+/, ".")
    |> String.replace(~r/(^\.|\.$)/, "")
  end

  defp calculate_complexity(path) do
    segments = String.split(path, ".")

    # Base score from segment count (increase multiplier)
    base_score = length(segments) * 2000

    # Exact segment matches are worth more at start of path
    exact_matches =
      Enum.with_index(segments)
      |> Enum.reduce(0, fn {segment, index}, acc ->
        case segment do
          "**" -> acc
          "*" -> acc
          # Higher weight for exact matches
          _ -> acc + 3000 * (length(segments) - index)
        end
      end)

    # Penalty calculation with position weighting
    penalties =
      Enum.with_index(segments)
      |> Enum.reduce(0, fn {segment, index}, acc ->
        case segment do
          # Double wildcard has massive penalty, reduced if it comes after exact matches
          "**" -> acc + 2000 - index * 200
          # Single wildcard has smaller penalty
          "*" -> acc + 1000 - index * 100
          _ -> acc
        end
      end)

    base_score + exact_matches - penalties
  end

  # Insert a HandlerInfo in descending order by (complexity, priority).
  defp insert_handler_sorted([], handler), do: [handler]

  defp insert_handler_sorted([h | t] = list, new_handler) do
    cond do
      new_handler.complexity > h.complexity ->
        [new_handler | list]

      new_handler.complexity < h.complexity ->
        [h | insert_handler_sorted(t, new_handler)]

      # complexities are equal, compare priority
      new_handler.priority > h.priority ->
        [new_handler | list]

      new_handler.priority < h.priority ->
        [h | insert_handler_sorted(t, new_handler)]

      # When both complexity and priority are equal, append the new handler
      true ->
        [h | [new_handler | t]]
    end
  end

  # Insert a PatternMatch in descending order by (complexity, priority).
  defp insert_matcher_sorted([], matcher), do: [matcher]

  defp insert_matcher_sorted([m | t] = list, new_matcher) do
    cond do
      new_matcher.complexity > m.complexity ->
        [new_matcher | list]

      new_matcher.complexity < m.complexity ->
        [m | insert_matcher_sorted(t, new_matcher)]

      new_matcher.priority > m.priority ->
        [new_matcher | list]

      new_matcher.priority < m.priority ->
        [m | insert_matcher_sorted(t, new_matcher)]

      # When both complexity and priority are equal, append the new matcher
      true ->
        [m | [new_matcher | t]]
    end
  end

  # Merge two descending-sorted lists (by {complexity, priority}).
  defp merge_sorted([], list2), do: list2
  defp merge_sorted(list1, []), do: list1

  defp merge_sorted([{_t1, p1, c1} = x | xs], [{_t2, p2, c2} = y | ys]) do
    cond do
      c1 > c2 ->
        [x | merge_sorted(xs, [y | ys])]

      c1 < c2 ->
        [y | merge_sorted([x | xs], ys)]

      # complexities are equal; compare priority
      p1 > p2 ->
        [x | merge_sorted(xs, [y | ys])]

      p1 < p2 ->
        [y | merge_sorted([x | xs], ys)]

      true ->
        [x | merge_sorted(xs, [y | ys])]
    end
  end

  # Core routing logic
  defp do_route([], %TrieNode{} = _trie, %Signal{} = _signal, acc), do: acc

  defp do_route([segment | rest] = _segments, %TrieNode{} = trie, %Signal{} = signal, acc) do
    # Try exact match first
    matching_handlers =
      case Map.get(trie.segments, segment) do
        nil ->
          acc

        %TrieNode{} = node ->
          handlers = collect_handlers(node.handlers, signal, acc)

          if rest == [] do
            handlers
          else
            do_route(rest, node, signal, handlers)
          end
      end

    # Then try single wildcard
    matching_handlers =
      case Map.get(trie.segments, "*") do
        nil ->
          matching_handlers

        %TrieNode{} = node ->
          handlers = collect_handlers(node.handlers, signal, matching_handlers)

          if rest == [] do
            handlers
          else
            do_route(rest, node, signal, handlers)
          end
      end

    # Finally try multi-level wildcard
    case Map.get(trie.segments, "**") do
      nil ->
        matching_handlers

      %TrieNode{} = node ->
        # Collect handlers from ** node first
        handlers = collect_handlers(node.handlers, signal, matching_handlers)
        # Iteratively try matching by consuming 0, 1, 2, ... segments
        do_route_multi_wildcard(node, rest, signal, handlers)
    end
  end

  # Iteratively match zero or more segments for ** wildcard
  # Preserves exact same traversal order as tails/1 approach
  @spec do_route_multi_wildcard(TrieNode.t(), [String.t()], Signal.t(), [HandlerInfo.t()]) ::
          [HandlerInfo.t()]
  defp do_route_multi_wildcard(node, segments, signal, acc) do
    # Try matching remaining path (zero-length ** match)
    acc = do_route(segments, node, signal, acc)

    # Try dropping one segment at a time (greedy ** matching)
    case segments do
      [] ->
        acc

      [_ | tail] ->
        do_route_multi_wildcard(node, tail, signal, acc)
    end
  end

  # Handler collection logic
  defp collect_handlers(%NodeHandlers{} = node_handlers, %Signal{} = signal, acc) do
    handler_results = extract_handler_results(node_handlers.handlers)
    pattern_results = collect_pattern_matches(node_handlers.matchers || [], signal)

    merge_sorted(
      merge_sorted(handler_results, pattern_results),
      acc
    )
  end

  defp collect_handlers(nil, %Signal{} = _signal, acc) do
    acc
  end

  # Extracts handler results from a list of handlers
  defp extract_handler_results(handlers) when is_list(handlers) do
    handlers
    |> Enum.flat_map(&expand_handler_targets/1)
  end

  defp extract_handler_results(_), do: []

  # Expands a single handler into target tuples
  defp expand_handler_targets(%{target: targets, priority: priority, complexity: complexity})
       when is_list(targets) do
    Enum.map(targets, fn target -> {target, priority, complexity} end)
  end

  defp expand_handler_targets(%{target: target, priority: priority, complexity: complexity}) do
    [{target, priority, complexity}]
  end

  # Pattern matching
  defp collect_pattern_matches(matchers, %Signal{} = signal) do
    Enum.reduce(matchers, [], fn %PatternMatch{} = matcher, matches ->
      try do
        case matcher.match.(signal) do
          true ->
            case matcher.target do
              targets when is_list(targets) ->
                # For multiple dispatch targets, create a tuple for each target
                Enum.map(targets, fn target ->
                  {target, matcher.priority, 0}
                end) ++ matches

              target ->
                [{target, matcher.priority, 0} | matches]
            end

          false ->
            matches

          _ ->
            matches
        end
      rescue
        _ ->
          matches
      end
    end)
  end

  # Route addition to trie
  defp do_add_path_route([segment], %TrieNode{} = trie, %HandlerInfo{} = handler_info) do
    # Expand multi-target routes into separate handlers
    handlers =
      case handler_info.target do
        targets when is_list(targets) ->
          Enum.map(targets, fn target ->
            %HandlerInfo{
              target: target,
              priority: handler_info.priority,
              complexity: handler_info.complexity
            }
          end)

        _ ->
          [handler_info]
      end

    Map.update(
      trie,
      :segments,
      %{segment => %TrieNode{handlers: %NodeHandlers{handlers: handlers}}},
      fn segments ->
        Map.update(
          segments,
          segment,
          %TrieNode{handlers: %NodeHandlers{handlers: handlers}},
          fn node ->
            %{
              node
              | handlers: %NodeHandlers{
                  handlers:
                    Enum.reduce(
                      handlers,
                      node.handlers.handlers || [],
                      fn handler, acc -> insert_handler_sorted(acc, handler) end
                    ),
                  matchers: node.handlers.matchers
                }
            }
          end
        )
      end
    )
  end

  defp do_add_path_route([segment | rest], %TrieNode{} = trie, %HandlerInfo{} = handler_info) do
    Map.update(
      trie,
      :segments,
      %{segment => do_add_path_route(rest, %TrieNode{}, handler_info)},
      fn segments ->
        Map.update(
          segments,
          segment,
          do_add_path_route(rest, %TrieNode{}, handler_info),
          fn node -> do_add_path_route(rest, node, handler_info) end
        )
      end
    )
  end

  defp do_add_pattern_route([segment], %TrieNode{} = trie, %PatternMatch{} = matcher) do
    # Expand multi-target routes into separate matchers
    matchers =
      case matcher.target do
        targets when is_list(targets) ->
          Enum.map(targets, fn target ->
            %PatternMatch{
              match: matcher.match,
              target: target,
              priority: matcher.priority,
              complexity: matcher.complexity
            }
          end)

        _ ->
          [matcher]
      end

    Map.update(
      trie,
      :segments,
      %{segment => %TrieNode{handlers: %NodeHandlers{matchers: matchers}}},
      fn segments ->
        Map.update(
          segments,
          segment,
          %TrieNode{handlers: %NodeHandlers{matchers: matchers}},
          fn node ->
            %{
              node
              | handlers: %NodeHandlers{
                  handlers: node.handlers.handlers,
                  matchers:
                    Enum.reduce(
                      matchers,
                      node.handlers.matchers || [],
                      fn m, acc -> insert_matcher_sorted(acc, m) end
                    )
                }
            }
          end
        )
      end
    )
  end

  defp do_add_pattern_route([segment | rest], %TrieNode{} = trie, %PatternMatch{} = matcher) do
    Map.update(
      trie,
      :segments,
      %{segment => do_add_pattern_route(rest, %TrieNode{}, matcher)},
      fn segments ->
        Map.update(
          segments,
          segment,
          do_add_pattern_route(rest, %TrieNode{}, matcher),
          fn node -> do_add_pattern_route(rest, node, matcher) end
        )
      end
    )
  end

  # Recursively removes a path from the trie and counts removed handlers
  defp do_remove_path([], trie), do: {trie, 0}

  defp do_remove_path([segment], %TrieNode{segments: segments} = trie) do
    # Count handlers at this leaf node before removing
    removed_count =
      case Map.get(segments, segment) do
        nil -> 0
        node -> count_handlers(node.handlers)
      end

    # Remove the leaf node
    new_segments = Map.delete(segments, segment)
    {%{trie | segments: new_segments}, removed_count}
  end

  defp do_remove_path([segment | rest], %TrieNode{segments: segments} = trie) do
    case Map.get(segments, segment) do
      nil ->
        {trie, 0}

      node ->
        {new_node, removed_count} = do_remove_path(rest, node)

        # If the node is empty after removal, remove it too
        if node_empty?(new_node) do
          {%{trie | segments: Map.delete(segments, segment)}, removed_count}
        else
          {%{trie | segments: Map.put(segments, segment, new_node)}, removed_count}
        end
    end
  end

  # Helper to count handlers in a NodeHandlers struct
  @spec count_handlers(NodeHandlers.t() | nil) :: non_neg_integer()
  defp count_handlers(nil), do: 0

  defp count_handlers(%NodeHandlers{handlers: handlers, matchers: matchers}) do
    handler_count = if is_list(handlers), do: length(handlers), else: 0
    matcher_count = if is_list(matchers), do: length(matchers), else: 0
    handler_count + matcher_count
  end

  # Helper to check if node is completely empty
  @spec node_empty?(TrieNode.t()) :: boolean()
  defp node_empty?(%TrieNode{} = node) do
    handlers_empty =
      case node.handlers do
        nil ->
          true

        %NodeHandlers{handlers: handlers, matchers: matchers} ->
          Enum.empty?(handlers || []) and Enum.empty?(matchers || [])
      end

    handlers_empty and map_size(node.segments) == 0
  end

  # Collects all routes from the trie into a list of Route structs
  defp collect_routes(%TrieNode{segments: segments, handlers: handlers}, acc, path_prefix) do
    # Add any handlers at current node
    acc =
      case handlers do
        %NodeHandlers{handlers: handlers}
        when is_list(handlers) and (is_list(handlers) and handlers != []) ->
          # Preserve order by not reversing here
          Enum.map(handlers, fn %HandlerInfo{
                                  target: target,
                                  priority: priority
                                } ->
            %Route{
              path: String.trim_leading(path_prefix, "."),
              target: target,
              priority: priority
            }
          end) ++ acc

        %NodeHandlers{matchers: matchers}
        when is_list(matchers) and (is_list(matchers) and matchers != []) ->
          # Preserve order by not reversing here
          Enum.map(matchers, fn %PatternMatch{
                                  target: target,
                                  priority: priority,
                                  match: match
                                } ->
            %Route{
              path: String.trim_leading(path_prefix, "."),
              target: target,
              priority: priority,
              match: match
            }
          end) ++ acc

        _ ->
          acc
      end

    # Recursively collect from child nodes
    segments
    # Sort segments for consistent ordering
    |> Enum.sort()
    |> Enum.reduce(acc, fn {segment, node}, acc ->
      new_prefix = path_prefix <> "." <> segment
      collect_routes(node, acc, new_prefix)
    end)
  end
end
