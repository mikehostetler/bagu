defmodule Moto.Agent.Verifiers.VerifyContext do
  @moduledoc false

  use Spark.Dsl.Verifier

  @impl true
  def verify(dsl_state) do
    module = Spark.Dsl.Verifier.get_persisted(dsl_state, :module)

    dsl_state
    |> Spark.Dsl.Verifier.get_entities([:context])
    |> Enum.reduce_while({:ok, MapSet.new()}, fn entry, {:ok, seen} ->
      with :ok <- validate_key(entry.key),
           :ok <- ensure_unique(entry.key, seen) do
        {:cont, {:ok, MapSet.put(seen, normalize_key(entry.key))}}
      else
        {:error, message} ->
          {:halt,
           {:error,
            Spark.Error.DslError.exception(
              message: message,
              path: [:context, :put],
              module: module,
              location: Spark.Dsl.Entity.anno(entry)
            )}}
      end
    end)
    |> case do
      {:ok, _seen} -> :ok
      other -> other
    end
  end

  defp validate_key(key) when is_atom(key), do: Moto.Context.validate_default(%{key => true})
  defp validate_key(key) when is_binary(key), do: Moto.Context.validate_default(%{key => true})

  defp validate_key(other),
    do: {:error, "context keys must be atoms or strings, got: #{inspect(other)}"}

  defp ensure_unique(key, seen) do
    normalized = normalize_key(key)

    if MapSet.member?(seen, normalized) do
      {:error, "duplicate context key #{inspect(key)} in Moto agent"}
    else
      :ok
    end
  end

  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key) when is_binary(key), do: String.trim(key)
end
