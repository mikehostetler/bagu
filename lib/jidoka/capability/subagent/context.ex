defmodule Jidoka.Subagent.Context do
  @moduledoc false

  @request_id_key :__jidoka_request_id__
  @server_key :__jidoka_server__
  @depth_key :__jidoka_subagent_depth__

  @spec request_id_key() :: atom()
  def request_id_key, do: @request_id_key

  @spec server_key() :: atom()
  def server_key, do: @server_key

  @spec depth_key() :: atom()
  def depth_key, do: @depth_key

  @spec current_depth(map()) :: non_neg_integer()
  def current_depth(context) when is_map(context) do
    case Map.get(context, @depth_key, 0) do
      depth when is_integer(depth) and depth >= 0 -> depth
      _ -> 0
    end
  end

  @spec child_context(map(), term()) :: map()
  def child_context(context, policy) when is_map(context) do
    context
    |> Jidoka.Context.sanitize_for_subagent()
    |> apply_forward_context_policy(policy)
    |> Map.put(@depth_key, current_depth(context) + 1)
  end

  @spec context_keys(map()) :: [String.t()]
  def context_keys(context) when is_map(context) do
    context
    |> Map.drop([@request_id_key, @server_key, @depth_key])
    |> Map.keys()
    |> Enum.map(&key_to_string/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.sort()
  end

  @spec map_keys(map()) :: [String.t()]
  def map_keys(map) when is_map(map) do
    map
    |> Map.keys()
    |> Enum.map(&key_to_string/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.sort()
  end

  @spec context_value(map(), atom() | String.t()) :: term()
  def context_value(context, key) when is_map(context) do
    case fetch_equivalent_key(context, key) do
      {:ok, _actual_key, value} -> value
      :error -> nil
    end
  end

  @spec peer_ref_preview(term(), map()) :: String.t()
  def peer_ref_preview({:context, key}, context) do
    case context_value(context, key) do
      peer_id when is_binary(peer_id) and peer_id != "" -> peer_id
      _ -> inspect({:context, key})
    end
  end

  def peer_ref_preview(peer_id, _context) when is_binary(peer_id), do: peer_id
  def peer_ref_preview(peer_ref, _context), do: inspect(peer_ref)

  @spec key_to_string(term()) :: String.t()
  def key_to_string(key) when is_atom(key), do: Atom.to_string(key)
  def key_to_string(key) when is_binary(key), do: key
  def key_to_string(key), do: inspect(key)

  defp apply_forward_context_policy(context, :public), do: context
  defp apply_forward_context_policy(_context, :none), do: %{}

  defp apply_forward_context_policy(context, {:only, keys}) when is_list(keys) do
    Enum.reduce(keys, %{}, fn key, acc ->
      case fetch_equivalent_key(context, key) do
        {:ok, actual_key, value} -> Map.put(acc, actual_key, value)
        :error -> acc
      end
    end)
  end

  defp apply_forward_context_policy(context, {:except, keys}) when is_list(keys) do
    Enum.reduce(keys, context, fn key, acc ->
      case fetch_equivalent_key(acc, key) do
        {:ok, actual_key, _value} -> Map.delete(acc, actual_key)
        :error -> acc
      end
    end)
  end

  defp apply_forward_context_policy(context, _policy), do: context

  defp fetch_equivalent_key(context, key) when is_map(context) do
    Enum.find_value(context, :error, fn {existing_key, value} ->
      if equivalent_key?(existing_key, key) do
        {:ok, existing_key, value}
      end
    end)
  end

  defp equivalent_key?(left, right), do: key_to_string(left) == key_to_string(right)
end
