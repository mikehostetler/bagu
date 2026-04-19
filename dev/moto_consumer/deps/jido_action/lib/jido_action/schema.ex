defmodule Jido.Action.Schema do
  @moduledoc """
  Unified schema validation interface supporting NimbleOptions, Zoi, and JSON Schema maps.

  This adapter provides a consistent API for:
  - Schema validation
  - Key introspection
  - Error formatting
  - JSON Schema generation (for AI tools)

  ## JSON Schema Maps

  Plain JSON Schema maps (e.g. produced by `json_spec`) are supported as a
  pass-through format. When a JSON Schema map is used:

  - Parameters are **not validated** at runtime (the schema is for the LLM only)
  - `known_keys/1` extracts atom keys from `"properties"` without creating new atoms
  - `to_json_schema/1` returns the map unchanged
  """

  @type t :: NimbleOptions.schema() | struct() | map() | []

  @doc """
  Detects the type of schema.

  Returns `:nimble` for NimbleOptions keyword list schemas, `:zoi` for Zoi schemas,
  `:json_schema` for plain JSON Schema maps, `:empty` for empty lists,
  or `:unknown` for unsupported types.
  """
  @spec schema_type(t()) :: :nimble | :zoi | :json_schema | :empty | :unknown
  def schema_type([]), do: :empty
  def schema_type(schema) when is_list(schema), do: :nimble

  def schema_type(%{"type" => "object", "properties" => props} = _schema)
      when is_map(props),
      do: :json_schema

  def schema_type(schema) do
    if impl_for_zoi_type?(schema) do
      :zoi
    else
      :unknown
    end
  end

  @doc """
  Validates data against a schema.

  For NimbleOptions schemas, returns `{:ok, map()}` with validated data as a map.
  For Zoi schemas, returns `{:ok, struct()}` with the validated struct.
  For empty schemas, returns the data unchanged.

  ## Parameters
    * `schema` - NimbleOptions schema (keyword list) or Zoi schema
    * `data` - Data to validate (map or keyword list)

  ## Returns
    * `{:ok, validated_data}` - Validation succeeded
    * `{:error, error}` - Validation failed
  """
  @spec validate(t(), map() | keyword()) :: {:ok, map()} | {:error, term()}
  def validate(schema, data) do
    case schema_type(schema) do
      :empty -> {:ok, data}
      :nimble -> validate_nimble(schema, data)
      :zoi -> validate_zoi(schema, data)
      :json_schema -> {:ok, data}
      :unknown -> {:error, "Unsupported schema type"}
    end
  end

  @doc """
  Extracts all known keys from a schema.

  ## Parameters
    * `schema` - NimbleOptions schema or Zoi schema

  ## Returns
    * List of atom keys defined in the schema
  """
  @spec known_keys(t()) :: [atom()]
  def known_keys([]), do: []
  def known_keys(schema) when is_list(schema), do: Keyword.keys(schema)

  def known_keys(%{"type" => "object", "properties" => props}) when is_map(props) do
    props
    |> json_schema_known_key_forms_from_properties()
    |> Enum.flat_map(fn
      %{atom: atom} when is_atom(atom) and not is_nil(atom) -> [atom]
      _ -> []
    end)
  end

  def known_keys(schema), do: extract_zoi_keys(schema)

  @doc false
  @spec json_schema_known_key_forms(t()) :: [%{atom: atom() | nil, string: String.t()}]
  def json_schema_known_key_forms(%{"type" => "object", "properties" => props})
      when is_map(props),
      do: json_schema_known_key_forms_from_properties(props)

  def json_schema_known_key_forms(_schema), do: []

  @doc """
  Converts a schema to JSON Schema format for AI tools.

  For NimbleOptions schemas, converts to OpenAI-compatible JSON Schema.
  For Zoi schemas, uses Zoi's built-in JSON Schema conversion.

  ## Parameters
    * `schema` - NimbleOptions schema or Zoi schema

  ## Returns
    * Map representing the JSON Schema
  """
  @spec to_json_schema(t()) :: map()
  def to_json_schema(schema), do: to_json_schema(schema, [])

  @doc """
  Converts a schema to JSON Schema format for AI tools with optional strictness controls.

  ## Options
    * `:strict` - when `true`, recursively sets `additionalProperties: false` on all
      object schemas (default: `false`)
  """
  @spec to_json_schema(t(), keyword()) :: map()
  def to_json_schema(schema, opts) do
    strict? = Keyword.get(opts, :strict, false)

    schema
    |> base_json_schema()
    |> maybe_apply_strict(strict?)
  end

  @doc """
  Formats validation errors into Jido.Action.Error structs.

  ## Parameters
    * `error` - The error from validation (NimbleOptions.ValidationError, Zoi.Error, or list)
    * `context` - Context string describing where the error occurred
    * `module` - The module where the error occurred

  ## Returns
    * `Jido.Action.Error.InvalidInputError.t()` - Formatted error struct
  """
  @spec format_error(term(), String.t(), module()) ::
          Jido.Action.Error.InvalidInputError.t()
  def format_error(error, context, module) do
    case error do
      %NimbleOptions.ValidationError{} = nimble_error ->
        nimble_error
        |> Jido.Action.Error.format_nimble_validation_error(context, module)
        |> Jido.Action.Error.validation_error()

      %Zoi.Error{} = zoi_error ->
        format_zoi_error(zoi_error, context, module)

      errors when is_list(errors) ->
        message = Zoi.prettify_errors(errors)

        Jido.Action.Error.validation_error(message, %{
          context: context,
          module: module,
          errors: format_zoi_error_list(errors)
        })

      _ ->
        Jido.Action.Error.validation_error("Validation failed", %{
          context: context,
          module: module
        })
    end
  end

  @doc """
  Validates a schema value for use in configuration.

  Used during compilation to ensure schema configuration is valid.

  ## Parameters
    * `value` - The schema value to validate
    * `_opts` - Options (unused, for Zoi refine compatibility)

  ## Returns
    * `:ok` - Schema is valid
    * `{:error, message}` - Schema is invalid
  """
  @spec validate_config_schema(term(), keyword()) :: :ok | {:error, String.t()}
  def validate_config_schema(value, _opts \\ [])

  def validate_config_schema(value, _opts) when is_list(value), do: :ok

  def validate_config_schema(%{"type" => "object", "properties" => props}, _opts)
      when is_map(props),
      do: :ok

  def validate_config_schema(value, _opts) do
    if impl_for_zoi_type?(value) do
      :ok
    else
      {:error, "must be NimbleOptions schema, Zoi schema, or JSON Schema map"}
    end
  end

  # Private Functions

  defp impl_for_zoi_type?(value) do
    is_struct(value) && Zoi.Type.impl_for(value) != nil
  rescue
    _ -> false
  end

  defp validate_nimble(schema, data) do
    data_kw = if is_map(data), do: Enum.to_list(data), else: data

    case NimbleOptions.validate(data_kw, schema) do
      {:ok, validated_kw} -> {:ok, Map.new(validated_kw)}
      {:error, error} -> {:error, error}
    end
  end

  defp validate_zoi(schema, data) do
    case Zoi.parse(schema, data) do
      {:ok, validated} -> {:ok, validated}
      {:error, errors} -> {:error, errors}
    end
  end

  defp extract_zoi_keys(%{__struct__: Zoi.Types.Map, fields: fields}) when is_map(fields) do
    Map.keys(fields)
  end

  defp extract_zoi_keys(%{__struct__: Zoi.Types.Map, fields: fields}) when is_list(fields) do
    Keyword.keys(fields)
  end

  defp extract_zoi_keys(%{__struct__: Zoi.Types.Struct, fields: fields}) when is_map(fields) do
    Map.keys(fields)
  end

  defp extract_zoi_keys(%{__struct__: Zoi.Types.Struct, fields: fields}) when is_list(fields) do
    Keyword.keys(fields)
  end

  defp extract_zoi_keys(_), do: []

  defp json_schema_known_key_forms_from_properties(properties) when is_map(properties) do
    properties
    |> Enum.reduce([], fn {raw_key, _schema}, acc ->
      case normalize_json_schema_key_form(raw_key) do
        nil -> acc
        form -> [form | acc]
      end
    end)
    |> Enum.reverse()
    |> Enum.uniq_by(& &1.string)
  end

  defp normalize_json_schema_key_form(key) when is_atom(key) do
    %{atom: key, string: Atom.to_string(key)}
  end

  defp normalize_json_schema_key_form(key) when is_binary(key) do
    %{atom: to_existing_atom_safe(key), string: key}
  end

  defp normalize_json_schema_key_form(_), do: nil

  defp to_existing_atom_safe(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end

  defp base_json_schema([]), do: %{"type" => "object", "properties" => %{}, "required" => []}
  defp base_json_schema(schema) when is_list(schema), do: nimble_to_json_schema(schema)

  defp base_json_schema(%{"type" => "object", "properties" => _} = schema), do: schema

  defp base_json_schema(schema), do: Zoi.to_json_schema(schema)

  defp maybe_apply_strict(schema, false), do: schema
  defp maybe_apply_strict(schema, true), do: disallow_additional_properties(schema)

  # Recursively set additionalProperties: false on all object schemas.
  # Handles both atom-key and string-key schemas for compatibility with Zoi and Nimble.
  defp disallow_additional_properties(%{type: :object} = schema) do
    schema
    |> Map.put(:additionalProperties, false)
    |> traverse_schema_values(&disallow_additional_properties/1)
  end

  defp disallow_additional_properties(%{"type" => "object"} = schema) do
    schema
    |> Map.put("additionalProperties", false)
    |> traverse_schema_values(&disallow_additional_properties/1)
  end

  defp disallow_additional_properties(schema) when is_map(schema) do
    traverse_schema_values(schema, &disallow_additional_properties/1)
  end

  defp disallow_additional_properties(schema) when is_list(schema) do
    Enum.map(schema, &disallow_additional_properties/1)
  end

  defp disallow_additional_properties(schema), do: schema

  defp traverse_schema_values(schema, fun) do
    schema
    |> maybe_update_key(:properties, &map_property_schemas(&1, fun))
    |> maybe_update_key("properties", &map_property_schemas(&1, fun))
    |> maybe_update_key(:items, fun)
    |> maybe_update_key("items", fun)
    |> maybe_update_key(:allOf, &map_schema_list(&1, fun))
    |> maybe_update_key("allOf", &map_schema_list(&1, fun))
    |> maybe_update_key(:anyOf, &map_schema_list(&1, fun))
    |> maybe_update_key("anyOf", &map_schema_list(&1, fun))
    |> maybe_update_key(:oneOf, &map_schema_list(&1, fun))
    |> maybe_update_key("oneOf", &map_schema_list(&1, fun))
    |> maybe_update_key(:not, fun)
    |> maybe_update_key("not", fun)
    |> maybe_update_key(:if, fun)
    |> maybe_update_key("if", fun)
    |> maybe_update_key(:then, fun)
    |> maybe_update_key("then", fun)
    |> maybe_update_key(:else, fun)
    |> maybe_update_key("else", fun)
    |> maybe_update_key(:contains, fun)
    |> maybe_update_key("contains", fun)
  end

  defp maybe_update_key(map, key, fun) do
    case Map.fetch(map, key) do
      {:ok, value} -> Map.put(map, key, fun.(value))
      :error -> map
    end
  end

  defp map_property_schemas(properties, fun) when is_map(properties) do
    Map.new(properties, fn {key, value} -> {key, fun.(value)} end)
  end

  defp map_property_schemas(properties, _fun), do: properties

  defp map_schema_list(value, fun) when is_list(value), do: Enum.map(value, fun)
  defp map_schema_list(value, _fun), do: value

  defp nimble_to_json_schema(nimble_schema) do
    properties =
      Enum.reduce(nimble_schema, %{}, fn {key, opts}, acc ->
        type_info = nimble_type_to_json(opts[:type])
        description = opts[:doc] || opts[:description] || "No description provided."

        field_schema =
          type_info
          |> maybe_add_description(description)
          |> maybe_add_enum(opts[:keys])

        Map.put(acc, to_string(key), field_schema)
      end)

    required =
      nimble_schema
      |> Enum.filter(fn {_key, opts} -> opts[:required] end)
      |> Enum.map(fn {key, _opts} -> to_string(key) end)

    %{
      "type" => "object",
      "properties" => properties,
      "required" => required
    }
  end

  defp nimble_type_to_json(:string), do: %{"type" => "string"}
  defp nimble_type_to_json(:integer), do: %{"type" => "integer"}
  defp nimble_type_to_json(:number), do: %{"type" => "number"}
  defp nimble_type_to_json(:boolean), do: %{"type" => "boolean"}
  defp nimble_type_to_json(:float), do: %{"type" => "number"}
  defp nimble_type_to_json(:non_neg_integer), do: %{"type" => "integer", "minimum" => 0}
  defp nimble_type_to_json(:pos_integer), do: %{"type" => "integer", "minimum" => 1}

  defp nimble_type_to_json(:timeout) do
    %{
      "oneOf" => [
        %{"type" => "integer", "minimum" => 0},
        %{"type" => "string", "enum" => ["infinity"]}
      ]
    }
  end

  defp nimble_type_to_json({:list, subtype}) do
    %{"type" => "array", "items" => nimble_type_to_json(subtype)}
  end

  defp nimble_type_to_json({:in, choices}) when is_list(choices) do
    inferred_type = infer_enum_type(choices)
    enum_values = normalize_enum_values(choices, inferred_type)
    base = %{"enum" => enum_values}
    if inferred_type, do: Map.put(base, "type", inferred_type), else: base
  end

  defp nimble_type_to_json(:keyword_list), do: %{"type" => "object"}
  defp nimble_type_to_json(:map), do: %{"type" => "object"}
  defp nimble_type_to_json({:map, _}), do: %{"type" => "object"}
  defp nimble_type_to_json(_), do: %{"type" => "string"}

  defp infer_enum_type(choices) do
    cond do
      Enum.all?(choices, &is_integer/1) -> "integer"
      Enum.all?(choices, &is_float/1) -> "number"
      Enum.all?(choices, &is_number/1) -> "number"
      Enum.all?(choices, &is_boolean/1) -> "boolean"
      Enum.all?(choices, &(is_binary(&1) or is_atom(&1))) -> "string"
      true -> nil
    end
  end

  defp normalize_enum_values(choices, "string") do
    Enum.map(choices, fn
      v when is_atom(v) -> Atom.to_string(v)
      v -> v
    end)
  end

  defp normalize_enum_values(choices, _type), do: choices

  defp maybe_add_description(schema, nil), do: schema
  defp maybe_add_description(schema, desc), do: Map.put(schema, "description", desc)

  defp maybe_add_enum(schema, nil), do: schema

  defp maybe_add_enum(schema, keys) when is_list(keys) do
    Map.put(schema, "enum", Enum.map(keys, &to_string/1))
  end

  defp format_zoi_error(error, context, module) do
    Jido.Action.Error.validation_error(error.message, %{
      context: context,
      module: module,
      path: error.path,
      code: error.code
    })
  end

  defp format_zoi_error_list(errors) when is_list(errors) do
    Enum.map(errors, fn
      %{path: path, message: message} = error ->
        %{
          path: path,
          message: message,
          code: Map.get(error, :code)
        }

      error ->
        %{message: inspect(error)}
    end)
  end
end
