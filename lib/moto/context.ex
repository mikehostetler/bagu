defmodule Moto.Context do
  @moduledoc false

  @request_hooks_key "__moto_hooks__"

  @type t :: map()

  @spec normalize(term()) :: {:ok, t()} | {:error, {:invalid_context, :expected_map}}
  def normalize(context) when is_map(context), do: {:ok, context}
  def normalize(context) when is_list(context), do: {:ok, Map.new(context)}
  def normalize(_context), do: {:error, {:invalid_context, :expected_map}}

  @spec merge(t(), t()) :: t()
  def merge(defaults, runtime) when is_map(defaults) and is_map(runtime) do
    Enum.reduce(runtime, defaults, fn {key, value}, acc ->
      acc
      |> drop_equivalent_keys(key)
      |> Map.put(key, value)
    end)
  end

  @spec validate_default(term()) :: :ok | {:error, String.t()}
  def validate_default(context) when is_map(context) do
    Enum.reduce_while(context, :ok, fn {key, _value}, :ok ->
      case validate_key(key) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  def validate_default(other),
    do: {:error, "context defaults must be maps, got: #{inspect(other)}"}

  defp validate_key(key) when is_atom(key) do
    validate_reserved_key(Atom.to_string(key))
  end

  defp validate_key(key) when is_binary(key) do
    trimmed = String.trim(key)

    cond do
      trimmed == "" ->
        {:error, "context keys must not be empty strings"}

      true ->
        validate_reserved_key(trimmed)
    end
  end

  defp validate_key(other),
    do: {:error, "context keys must be atoms or strings, got: #{inspect(other)}"}

  defp validate_reserved_key(@request_hooks_key) do
    {:error, "context key #{@request_hooks_key} is reserved for Moto internals"}
  end

  defp validate_reserved_key(_key), do: :ok

  defp drop_equivalent_keys(acc, key) do
    Enum.reduce(Map.keys(acc), acc, fn existing_key, memo ->
      if existing_key != key and equivalent_keys?(existing_key, key) do
        Map.delete(memo, existing_key)
      else
        memo
      end
    end)
  end

  defp equivalent_keys?(left, right) when is_atom(left) and is_binary(right),
    do: Atom.to_string(left) == right

  defp equivalent_keys?(left, right) when is_binary(left) and is_atom(right),
    do: left == Atom.to_string(right)

  defp equivalent_keys?(_left, _right), do: false
end
