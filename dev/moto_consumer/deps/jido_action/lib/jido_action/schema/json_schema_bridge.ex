defmodule Jido.Action.Schema.JsonSchemaBridge do
  @moduledoc false

  @object_keywords ["type", "properties", "required", "additionalProperties", "description"]
  @array_keywords ["type", "items", "description"]
  @primitive_keywords ["type", "enum", "description"]

  @type fallback_reason ::
          :invalid_schema
          | :unsupported_root
          | {:invalid_required, term()}
          | {:unsupported_keyword, String.t()}
          | {:unsupported_type, term()}

  @spec to_zoi(map()) :: {:ok, Zoi.schema()} | {:fallback, fallback_reason()}
  def to_zoi(schema) when is_map(schema) and not is_struct(schema) do
    case build_schema(schema, 0) do
      {:ok, zoi_schema} -> {:ok, zoi_schema}
      {:error, reason} -> {:fallback, reason}
    end
  end

  def to_zoi(_schema), do: {:fallback, :invalid_schema}

  @spec convert_params(map(), map()) ::
          {:ok, map()} | {:fallback, fallback_reason() | {:parse_error, term()}}
  def convert_params(params, json_schema) when is_map(params) and not is_struct(params) do
    with {:ok, zoi_schema} <- to_zoi(json_schema),
         normalized <- normalize_atom_precedence(params, json_schema),
         {:ok, parsed} <- Zoi.parse(zoi_schema, normalized, coerce: true) do
      {:ok, parsed}
    else
      {:fallback, _reason} = fallback ->
        fallback

      {:error, reason} ->
        {:fallback, {:parse_error, reason}}
    end
  end

  def convert_params(_params, _json_schema), do: {:fallback, :invalid_schema}

  defp build_schema(schema, depth) do
    case fetch_value(schema, "type") do
      "object" ->
        build_object(schema, depth)

      "array" ->
        build_array(schema, depth)

      type when type in ["string", "integer", "number", "boolean"] ->
        build_primitive(schema, depth)

      other ->
        {:error, {:unsupported_type, other}}
    end
  end

  defp build_object(schema, depth) do
    with :ok <- ensure_allowed_keywords(schema, @object_keywords),
         properties when is_map(properties) <- fetch_value(schema, "properties"),
         {:ok, required_keys} <- parse_required(fetch_value(schema, "required")),
         :ok <- validate_additional_properties(fetch_value(schema, "additionalProperties")),
         {:ok, fields} <- build_object_fields(properties, required_keys, depth) do
      opts = [coerce: true, unrecognized_keys: :preserve] ++ description_opts(schema)
      {:ok, Zoi.object(fields, opts)}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_schema}
    end
  end

  defp build_array(schema, depth) do
    with :ok <- ensure_allowed_keywords(schema, @array_keywords),
         items when is_map(items) <- fetch_value(schema, "items"),
         {:ok, inner} <- build_schema(items, depth + 1) do
      {:ok, Zoi.array(inner, description_opts(schema))}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_schema}
    end
  end

  defp build_primitive(schema, _depth) do
    with :ok <- ensure_allowed_keywords(schema, @primitive_keywords),
         type when type in ["string", "integer", "number", "boolean"] <-
           fetch_value(schema, "type"),
         {:ok, zoi_schema} <- build_primitive_type(type, fetch_value(schema, "enum"), schema) do
      {:ok, zoi_schema}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_schema}
    end
  end

  defp build_primitive_type(_type, enum_values, schema)
       when is_list(enum_values),
       do: {:ok, Zoi.enum(enum_values, description_opts(schema))}

  defp build_primitive_type("string", nil, schema),
    do: {:ok, Zoi.string(description_opts(schema))}

  defp build_primitive_type("integer", nil, schema),
    do: {:ok, Zoi.integer(description_opts(schema))}

  defp build_primitive_type("number", nil, schema),
    do: {:ok, Zoi.number(description_opts(schema))}

  defp build_primitive_type("boolean", nil, schema),
    do: {:ok, Zoi.boolean(description_opts(schema))}

  defp build_primitive_type(_type, _enum_values, _schema), do: {:error, :invalid_schema}

  defp build_object_fields(properties, required_keys, depth) do
    Enum.reduce_while(properties, {:ok, %{}}, fn {key, property_schema}, {:ok, fields} ->
      with {:ok, string_key} <- normalize_property_key(key),
           true <- is_map(property_schema) and not is_struct(property_schema),
           {:ok, zoi_schema} <- build_schema(property_schema, depth + 1) do
        field_key = choose_field_key(key, string_key, depth)

        field_schema =
          if Enum.member?(required_keys, string_key),
            do: zoi_schema,
            else: Zoi.optional(zoi_schema)

        {:cont, {:ok, Map.put(fields, field_key, field_schema)}}
      else
        false -> {:halt, {:error, :invalid_schema}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp normalize_property_key(key) when is_binary(key), do: {:ok, key}
  defp normalize_property_key(key) when is_atom(key), do: {:ok, Atom.to_string(key)}
  defp normalize_property_key(_), do: {:error, :invalid_schema}

  defp choose_field_key(_key, string_key, depth) when depth > 0, do: string_key

  defp choose_field_key(key, _string_key, 0) when is_atom(key), do: key

  defp choose_field_key(key, string_key, 0) when is_binary(key) do
    case to_existing_atom_safe(string_key) do
      nil -> string_key
      atom -> atom
    end
  end

  defp fetch_value(map, "type"), do: Map.get(map, "type", Map.get(map, :type))
  defp fetch_value(map, "properties"), do: Map.get(map, "properties", Map.get(map, :properties))
  defp fetch_value(map, "required"), do: Map.get(map, "required", Map.get(map, :required))

  defp fetch_value(map, "additionalProperties"),
    do: Map.get(map, "additionalProperties", Map.get(map, :additionalProperties))

  defp fetch_value(map, "description"),
    do: Map.get(map, "description", Map.get(map, :description))

  defp fetch_value(map, "items"), do: Map.get(map, "items", Map.get(map, :items))
  defp fetch_value(map, "enum"), do: Map.get(map, "enum", Map.get(map, :enum))
  defp fetch_value(map, key), do: Map.get(map, key)

  defp parse_required(nil), do: {:ok, []}
  defp parse_required([]), do: {:ok, []}

  defp parse_required(required) when is_list(required) do
    if Enum.all?(required, &is_binary/1) do
      {:ok, Enum.uniq(required)}
    else
      {:error, {:invalid_required, required}}
    end
  end

  defp parse_required(required), do: {:error, {:invalid_required, required}}

  defp validate_additional_properties(nil), do: :ok
  defp validate_additional_properties(value) when is_boolean(value), do: :ok
  defp validate_additional_properties(_value), do: {:error, :invalid_schema}

  defp ensure_allowed_keywords(map, allowed_keywords) do
    map
    |> Map.keys()
    |> Enum.reduce_while(:ok, fn key, :ok ->
      case normalize_property_key(key) do
        {:ok, normalized_key} ->
          if Enum.member?(allowed_keywords, normalized_key) do
            {:cont, :ok}
          else
            {:halt, {:error, {:unsupported_keyword, normalized_key}}}
          end

        {:error, _} ->
          {:halt, {:error, :invalid_schema}}
      end
    end)
  end

  defp description_opts(schema) do
    case fetch_value(schema, "description") do
      description when is_binary(description) -> [description: description]
      _ -> []
    end
  end

  defp normalize_atom_precedence(params, schema) do
    schema
    |> Jido.Action.Schema.json_schema_known_key_forms()
    |> Enum.reduce(params, fn
      %{atom: atom, string: string}, acc when is_atom(atom) and not is_nil(atom) ->
        if Map.has_key?(acc, atom), do: Map.delete(acc, string), else: acc

      _form, acc ->
        acc
    end)
  end

  defp to_existing_atom_safe(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end
end
