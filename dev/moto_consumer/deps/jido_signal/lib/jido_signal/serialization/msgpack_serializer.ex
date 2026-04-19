if Code.ensure_loaded?(Msgpax) do
  defmodule Jido.Signal.Serialization.MsgpackSerializer do
    @moduledoc """
    A serializer that uses the MessagePack format via the Msgpax library.

    MessagePack is a binary serialization format that is more compact than JSON
    but still platform-independent, making it ideal for network communication
    and storage.

    ## Features

    - More compact than JSON
    - Preserves more data types than JSON
    - Cross-platform compatibility
    - Fast serialization/deserialization

    ## Usage

        # Configure as default serializer
        config :jido, :default_serializer, Jido.Signal.Serialization.MsgpackSerializer

        # Or use explicitly
        Signal.serialize(signal, serializer: Jido.Signal.Serialization.MsgpackSerializer)

    ## Type Handling

    MessagePack has limitations compared to Erlang terms:
    - Atoms are converted to strings
    - Tuples are converted to arrays
    - Custom structs need explicit handling
    """

    @behaviour Jido.Signal.Serialization.Serializer

    alias Jido.Signal.Serialization.CloudEventsTransform
    alias Jido.Signal.Serialization.Config
    alias Jido.Signal.Serialization.TypeProvider

    @doc """
    Serialize given term to MessagePack binary format.
    """
    @impl true
    def serialize(term, _opts \\ []) do
      # Pre-process the term to handle Elixir-specific types
      prepared = prepare_for_serialization(term)
      preprocessed = preprocess_for_msgpack(prepared)

      case Msgpax.pack(preprocessed) do
        {:ok, iodata} -> {:ok, IO.iodata_to_binary(iodata)}
        {:error, reason} -> {:error, reason}
      end
    rescue
      e -> {:error, Exception.message(e)}
    end

    @doc """
    Deserialize given MessagePack binary data back to the original format.
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
      case Msgpax.unpack(binary) do
        {:ok, unpacked} ->
          process_unpacked_data(unpacked, config)

        {:error, reason} ->
          {:error, {:msgpack_decode_failed, reason}}
      end
    rescue
      e in ArgumentError ->
        {:error, {:msgpack_deserialize_failed, Exception.message(e)}}

      e ->
        {:error, {:msgpack_deserialize_failed, Exception.message(e)}}
    end

    defp process_unpacked_data(unpacked, config) do
      inflated = CloudEventsTransform.inflate_for_deserialization(unpacked)
      result = deserialize_with_type(inflated, config)
      {:ok, result}
    end

    defp deserialize_with_type(unpacked, config) do
      case Keyword.get(config, :type) do
        nil ->
          postprocess_from_msgpack(unpacked)

        type_str ->
          deserialize_to_struct(unpacked, type_str, config)
      end
    end

    defp deserialize_to_struct(unpacked, type_str, config) do
      type_provider = Keyword.get(config, :type_provider, TypeProvider)
      target_struct = type_provider.to_struct(type_str)
      processed = postprocess_from_msgpack(unpacked)

      if is_map(processed) and not is_struct(processed) do
        safe_build_struct(target_struct.__struct__, processed)
      else
        processed
      end
    end

    defp safe_build_struct(mod, data) do
      # Only assign known fields; do not create new atoms
      permitted = Map.keys(struct(mod)) -- [:__struct__]

      attrs =
        for k <- permitted, into: %{} do
          ks = if is_atom(k), do: Atom.to_string(k), else: k
          {k, Map.get(data, ks, Map.get(data, k))}
        end

      struct(mod, attrs)
    end

    # Pre-process Elixir data for MessagePack serialization
    defp preprocess_for_msgpack(data) when is_map(data) do
      base_map = if is_struct(data), do: Map.from_struct(data), else: data

      base_map
      |> Map.new(fn {k, v} ->
        {preprocess_for_msgpack(k), preprocess_for_msgpack(v)}
      end)
    end

    defp preprocess_for_msgpack(data) when is_list(data) do
      Enum.map(data, &preprocess_for_msgpack/1)
    end

    defp preprocess_for_msgpack(data) when is_tuple(data) do
      # Convert tuples to tagged maps for better round-trip
      %{"__tuple__" => data |> Tuple.to_list() |> Enum.map(&preprocess_for_msgpack/1)}
    end

    defp preprocess_for_msgpack(data)
         when is_atom(data) and not is_nil(data) and not is_boolean(data) do
      # Convert atoms to strings, but preserve nil and booleans
      Atom.to_string(data)
    end

    defp preprocess_for_msgpack(data), do: data

    # Post-process MessagePack data back to Elixir types
    defp postprocess_from_msgpack(%{"__tuple__" => list}) when is_list(list) do
      # Restore tuples from tagged arrays
      list
      |> Enum.map(&postprocess_from_msgpack/1)
      |> List.to_tuple()
    end

    defp postprocess_from_msgpack(data) when is_map(data) do
      data
      |> Map.new(fn {k, v} ->
        {postprocess_from_msgpack(k), postprocess_from_msgpack(v)}
      end)
    end

    defp postprocess_from_msgpack(data) when is_list(data) do
      Enum.map(data, &postprocess_from_msgpack/1)
    end

    defp postprocess_from_msgpack(data), do: data

    @doc """
    Checks if the given binary is valid MessagePack data.
    """
    @spec valid_msgpack?(binary()) :: boolean()
    def valid_msgpack?(binary) when is_binary(binary) do
      case Msgpax.unpack(binary) do
        {:ok, _} -> true
        {:error, _} -> false
      end
    end

    def valid_msgpack?(_), do: false

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
