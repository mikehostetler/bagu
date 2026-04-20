defmodule Moto.Context do
  @moduledoc false

  @reserved_keys [
    "__moto_hooks__",
    "__moto_guardrails__",
    "__moto_memory__",
    "__tool_guardrail_callback__",
    "__moto_request_id__",
    "__moto_server__",
    "__moto_subagent_depth__"
  ]

  @type t :: map()

  @spec normalize(term()) :: {:ok, t()} | {:error, {:invalid_context, :expected_map}}
  def normalize(context) do
    case coerce_map(context) do
      {:ok, normalized} -> {:ok, normalized}
      :error -> {:error, {:invalid_context, :expected_map}}
    end
  end

  @spec coerce_map(term()) :: {:ok, t()} | :error
  def coerce_map(context) when is_map(context), do: {:ok, context}

  def coerce_map(context) when is_list(context) do
    if Keyword.keyword?(context) do
      {:ok, Map.new(context)}
    else
      :error
    end
  end

  def coerce_map(_context), do: :error

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

  @spec strip_internal(t()) :: t()
  def strip_internal(context) when is_map(context) do
    Enum.reduce(Map.keys(context), context, fn key, acc ->
      if internal_key?(key) do
        Map.delete(acc, key)
      else
        acc
      end
    end)
  end

  @spec sanitize_for_subagent(t()) :: t()
  def sanitize_for_subagent(context) when is_map(context) do
    context
    |> strip_internal()
    |> Map.delete(:memory)
    |> Map.delete("memory")
  end

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

  defp validate_reserved_key(key) when key in @reserved_keys,
    do: {:error, "context key #{key} is reserved for Moto internals"}

  defp validate_reserved_key(_key), do: :ok

  defp internal_key?(key) when is_atom(key) do
    internal_key?(Atom.to_string(key))
  end

  defp internal_key?(key) when is_binary(key), do: String.trim(key) in @reserved_keys
  defp internal_key?(_key), do: false

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
