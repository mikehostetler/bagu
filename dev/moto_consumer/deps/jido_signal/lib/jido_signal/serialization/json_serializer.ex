#
# Json Serializer from Commanded: https://github.com/commanded/commanded/blob/master/lib/commanded/serialization/json_serializer.ex
# License: MIT
#
if Code.ensure_loaded?(Jason) do
  defmodule Jido.Signal.Serialization.JsonSerializer do
    @moduledoc """
    A serializer that uses the JSON format and Jason library.
    """

    @behaviour Jido.Signal.Serialization.Serializer

    alias Jido.Signal.Serialization.CloudEventsTransform
    alias Jido.Signal.Serialization.Config
    alias Jido.Signal.Serialization.JsonDecoder
    alias Jido.Signal.Serialization.Schema
    alias Jido.Signal.Serialization.TypeProvider

    @doc """
    Serialize given term to JSON binary data.
    """
    @impl true
    def serialize(term, _opts \\ []) do
      serializable_term = prepare_for_serialization(term)
      {:ok, Jason.encode!(serializable_term)}
    rescue
      e -> {:error, Exception.message(e)}
    end

    @doc """
    Deserialize given JSON binary data to the expected type.
    """
    @impl true
    def deserialize(binary, config \\ []) when is_binary(binary) do
      max_size = Config.max_payload_bytes()

      if byte_size(binary) > max_size do
        {:error, {:payload_too_large, byte_size(binary), max_size}}
      else
        do_deserialize(binary, config)
      end
    end

    defp do_deserialize(binary, config) do
      {type, opts} =
        case Keyword.get(config, :type) do
          nil ->
            {nil, []}

          type_str ->
            type_provider = Keyword.get(config, :type_provider, TypeProvider)

            case type_provider.to_struct(type_str) do
              {:error, reason} ->
                throw({:unknown_type, type_str, reason})

              target_struct ->
                {target_struct, []}
            end
        end

      decoded =
        binary
        |> Jason.decode!(opts)
        |> CloudEventsTransform.inflate_for_deserialization()

      validated =
        if CloudEventsTransform.signal_map?(decoded) do
          case Schema.validate_signal(decoded) do
            {:ok, valid} -> valid
            {:error, errors} -> throw({:schema_validation_failed, errors})
          end
        else
          decoded
        end

      result =
        validated
        |> to_struct(type)
        |> JsonDecoder.decode()

      {:ok, result}
    rescue
      e in Jason.DecodeError ->
        {:error, {:json_decode_failed, Exception.message(e)}}

      e in ArgumentError ->
        {:error, {:json_deserialize_failed, Exception.message(e)}}

      e ->
        {:error, {:json_deserialize_failed, Exception.message(e)}}
    catch
      {:unknown_type, type_str, reason} ->
        {:error, {:unknown_type, type_str, reason}}

      {:schema_validation_failed, errors} ->
        {:error, {:schema_validation_failed, errors}}
    end

    defp to_struct(data, nil), do: data

    defp to_struct(data, %mod{} = _struct) when is_map(data) do
      safe_build_struct(mod, data)
    end

    defp to_struct(data, mod) when is_atom(mod) and is_map(data) do
      safe_build_struct(mod, data)
    end

    defp to_struct(data, _mod), do: data

    defp safe_build_struct(mod, data) do
      # Only assign known fields; do not create new atoms
      permitted = Map.keys(struct(mod)) -- [:__struct__]

      attrs =
        for k <- permitted, into: %{} do
          ks = Atom.to_string(k)
          {k, Map.get(data, ks, Map.get(data, k))}
        end

      struct(mod, attrs)
    end

    # Prepare term for serialization by flattening extensions in Signal structs
    defp prepare_for_serialization(%Jido.Signal{} = signal) do
      signal
      |> CloudEventsTransform.flatten_for_serialization()
      |> Map.put("jido_schema_version", 1)
    end

    defp prepare_for_serialization(signals) when is_list(signals) do
      Enum.map(signals, &prepare_for_serialization/1)
    end

    defp prepare_for_serialization(term), do: term
  end
end
