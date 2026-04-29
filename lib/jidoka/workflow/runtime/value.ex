defmodule Jidoka.Workflow.Runtime.Value do
  @moduledoc false

  alias Jidoka.Workflow.Runtime.Keys

  @state_key Keys.state_key()

  @spec extract_state!(map()) :: map()
  def extract_state!(%{@state_key => state}) when is_map(state), do: state

  def extract_state!(%{input: input}) when is_list(input) do
    input
    |> Enum.map(&extract_state_from_fact!/1)
    |> merge_states()
  end

  def extract_state!(%{input: input}) do
    extract_state_from_fact!(input)
  end

  def extract_state!(other) do
    raise ArgumentError, "expected Jidoka workflow state fact, got: #{inspect(other)}"
  end

  @spec extract_state_from_fact!(term()) :: map()
  def extract_state_from_fact!(%{@state_key => state}) when is_map(state), do: state
  def extract_state_from_fact!(state) when is_map(state) and is_map_key(state, :steps), do: state

  def extract_state_from_fact!(facts) when is_list(facts),
    do: facts |> Enum.map(&extract_state_from_fact!/1) |> merge_states()

  def extract_state_from_fact!(other) do
    raise ArgumentError, "expected Jidoka workflow state fact, got: #{inspect(other)}"
  end

  @spec select_final_state(map(), [term()]) :: map()
  def select_final_state(definition, productions) do
    states = Enum.map(productions, &extract_state_from_fact!/1)

    states
    |> Enum.reverse()
    |> Enum.find(fn state -> match?({:ok, _}, resolve_value(definition.output, state)) end)
    |> case do
      nil -> states |> Enum.reverse() |> Enum.max_by(&map_size(&1.steps))
      state -> state
    end
  end

  @spec resolve_value(term(), map()) :: {:ok, term()} | {:error, term()}
  def resolve_value({:jidoka_workflow_ref, :input, key}, state), do: fetch_ref(state.input, key, :input)
  def resolve_value({:jidoka_workflow_ref, :context, key}, state), do: fetch_ref(state.context, key, :context)
  def resolve_value({:jidoka_workflow_ref, :value, value}, _state), do: {:ok, value}

  def resolve_value({:jidoka_workflow_ref, :from, step, nil}, state), do: fetch_ref(state.steps, step, :step)

  def resolve_value({:jidoka_workflow_ref, :from, step, path}, state) when is_list(path) do
    with {:ok, value} <- fetch_ref(state.steps, step, :step) do
      resolve_path(value, path)
    end
  end

  def resolve_value(%{} = map, state) do
    Enum.reduce_while(map, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      case resolve_value(value, state) do
        {:ok, resolved} -> {:cont, {:ok, Map.put(acc, key, resolved)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  def resolve_value(list, state) when is_list(list) do
    list
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, acc} ->
      case resolve_value(value, state) do
        {:ok, resolved} -> {:cont, {:ok, [resolved | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end

  def resolve_value(tuple, state) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> resolve_value(state)
    |> case do
      {:ok, values} -> {:ok, List.to_tuple(values)}
      error -> error
    end
  end

  def resolve_value(value, _state), do: {:ok, value}

  @spec fetch_equivalent(map(), term()) :: {:ok, term()} | :error
  def fetch_equivalent(map, key) when is_map(map) do
    cond do
      Map.has_key?(map, key) ->
        {:ok, Map.fetch!(map, key)}

      is_atom(key) and Map.has_key?(map, Atom.to_string(key)) ->
        {:ok, Map.fetch!(map, Atom.to_string(key))}

      is_binary(key) ->
        case Enum.find(Map.keys(map), &(is_atom(&1) and Atom.to_string(&1) == key)) do
          nil -> :error
          existing -> {:ok, Map.fetch!(map, existing)}
        end

      true ->
        :error
    end
  end

  @spec has_equivalent_key?(map(), term()) :: boolean()
  def has_equivalent_key?(map, key) when is_map(map), do: match?({:ok, _}, fetch_equivalent(map, key))

  defp merge_states([state]), do: state

  defp merge_states([first | rest]) do
    Enum.reduce(rest, first, fn state, acc ->
      %{acc | steps: Map.merge(acc.steps, state.steps)}
    end)
  end

  defp merge_states([]), do: raise(ArgumentError, "expected at least one Jidoka workflow state")

  defp resolve_path(value, []), do: {:ok, value}

  defp resolve_path(value, [key | rest]) when is_map(value) do
    case fetch_ref(value, key, :field) do
      {:ok, nested} -> resolve_path(nested, rest)
      {:error, {:missing_ref, :field, _key}} -> {:error, {:missing_field, [key | rest], value}}
    end
  end

  defp resolve_path(value, path), do: {:error, {:missing_field, path, value}}

  defp fetch_ref(map, key, kind) when is_map(map) do
    case fetch_equivalent(map, key) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, {:missing_ref, kind, key}}
    end
  end
end
