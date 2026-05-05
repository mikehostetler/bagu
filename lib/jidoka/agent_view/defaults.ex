defmodule Jidoka.AgentView.Defaults do
  @moduledoc false

  @spec conversation_id(term()) :: String.t()
  def conversation_id(%Jidoka.Session{conversation_id: conversation_id}), do: conversation_id

  def conversation_id(input) do
    input
    |> input_value(:conversation_id)
    |> normalize_id("default")
  end

  @spec agent_id(module(), String.t()) :: String.t()
  def agent_id(agent, conversation_id) when is_atom(agent) and is_binary(conversation_id) do
    base =
      if function_exported?(agent, :id, 0) do
        apply(agent, :id, [])
      else
        agent
        |> Module.split()
        |> List.last()
        |> Macro.underscore()
      end

    "#{base}-#{conversation_id}"
  end

  @spec runtime_context(term(), String.t()) :: map()
  def runtime_context(%Jidoka.Session{context: context}, _conversation_id), do: context

  def runtime_context(_input, conversation_id), do: %{session: conversation_id}

  @spec normalize_id(term(), String.t()) :: String.t()
  def normalize_id(value, default \\ "default")

  def normalize_id(nil, default), do: default

  def normalize_id(value, default) do
    value
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_]+/, "_")
    |> String.trim("_")
    |> case do
      "" -> default
      id -> id
    end
  end

  defp input_value(input, key) when is_list(input) and is_atom(key) do
    Keyword.get(input, key)
  end

  defp input_value(%{} = input, key) when is_atom(key) do
    Map.get(input, key, Map.get(input, Atom.to_string(key)))
  end

  defp input_value(_input, _key), do: nil
end
