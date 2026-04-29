defmodule Jidoka.Model do
  @moduledoc false

  @doc false
  @spec model_aliases() :: %{optional(atom()) => term()}
  def model_aliases do
    case Application.get_env(:jidoka, :model_aliases, %{}) do
      aliases when is_map(aliases) -> aliases
      _ -> %{}
    end
  end

  @doc false
  @spec model(Jido.AI.model_input()) :: ReqLLM.model_input()
  def model(model) when is_atom(model) do
    case model_aliases() do
      %{^model => resolved} -> resolved
      _ -> Jido.AI.resolve_model(model)
    end
  end

  def model(model) when is_binary(model) do
    trimmed = String.trim(model)

    case resolve_string_alias(trimmed) do
      {:ok, alias_name} -> model(alias_name)
      :error -> Jido.AI.resolve_model(trimmed)
    end
  end

  def model(model), do: Jido.AI.resolve_model(model)

  defp resolve_string_alias(name) when is_binary(name) do
    known_aliases =
      Map.keys(model_aliases()) ++
        Map.keys(Jido.AI.model_aliases())

    case Enum.find(known_aliases, &(Atom.to_string(&1) == name)) do
      nil -> :error
      alias_name -> {:ok, alias_name}
    end
  end
end
