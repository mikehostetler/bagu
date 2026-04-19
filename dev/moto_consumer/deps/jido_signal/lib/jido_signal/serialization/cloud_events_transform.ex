defmodule Jido.Signal.Serialization.CloudEventsTransform do
  @moduledoc false
  # Internal module for CloudEvents extension transformations shared across serializers.

  @doc """
  Flattens Signal extensions for serialization.

  Delegates to Jido.Signal.flatten_extensions/1 for Signals.
  """
  def flatten_for_serialization(%Jido.Signal{} = signal) do
    Jido.Signal.flatten_extensions(signal)
  end

  def flatten_for_serialization(term), do: term

  @doc """
  Inflates CloudEvents attributes back into Signal extensions during deserialization.

  Handles both single maps and lists of maps.
  """
  def inflate_for_deserialization(data) when is_list(data) do
    Enum.map(data, &inflate_for_deserialization/1)
  end

  def inflate_for_deserialization(data) when is_map(data) and not is_struct(data) do
    if signal_map?(data) do
      # Convert keys to strings for consistent processing (handles Erlang term format)
      string_keyed_data = Map.new(data, fn {k, v} -> {to_string(k), v} end)
      {extensions, remaining} = Jido.Signal.inflate_extensions(string_keyed_data)

      if Enum.empty?(extensions) do
        remaining
      else
        Map.put(remaining, "extensions", extensions)
      end
    else
      data
    end
  end

  def inflate_for_deserialization(data) when is_map(data), do: data

  def inflate_for_deserialization(data), do: data

  @doc """
  Checks if a map represents a CloudEvents/Signal structure.

  A map is considered a Signal if it has 'type' and 'source' fields,
  and either 'specversion' or 'id'.
  """
  def signal_map?(data) when is_map(data) do
    (Map.has_key?(data, "type") or Map.has_key?(data, :type)) and
      (Map.has_key?(data, "source") or Map.has_key?(data, :source)) and
      (Map.has_key?(data, "specversion") or Map.has_key?(data, :specversion) or
         Map.has_key?(data, "id") or Map.has_key?(data, :id))
  end

  def signal_map?(_), do: false
end
