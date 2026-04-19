defmodule Moto.Interrupt do
  @moduledoc """
  Structured human-in-the-loop or approval interrupt returned by Moto agents.
  """

  @enforce_keys [:id, :kind, :message, :data]
  defstruct [:id, :kind, :message, :data]

  @type t :: %__MODULE__{
          id: String.t(),
          kind: atom() | String.t(),
          message: String.t(),
          data: map()
        }

  @spec new(map() | keyword() | t()) :: t()
  def new(%__MODULE__{} = interrupt), do: interrupt

  def new(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = Map.new(attrs)

    %__MODULE__{
      id: normalize_id(Map.get(attrs, :id, Map.get(attrs, "id"))),
      kind: Map.get(attrs, :kind, Map.get(attrs, "kind", :interrupt)),
      message: normalize_message(Map.get(attrs, :message, Map.get(attrs, "message"))),
      data: normalize_data(Map.get(attrs, :data, Map.get(attrs, "data", %{})))
    }
  end

  def new(other) do
    raise ArgumentError,
          "Moto.Interrupt.new/1 expected a map, keyword list, or interrupt struct, got: #{inspect(other)}"
  end

  defp normalize_id(id) when is_binary(id) and id != "", do: id
  defp normalize_id(_), do: Jido.Signal.ID.generate!()

  defp normalize_message(message) when is_binary(message) and message != "", do: message
  defp normalize_message(_), do: "Moto agent interrupted"

  defp normalize_data(data) when is_map(data), do: data
  defp normalize_data(data) when is_list(data), do: Map.new(data)
  defp normalize_data(_), do: %{}
end
