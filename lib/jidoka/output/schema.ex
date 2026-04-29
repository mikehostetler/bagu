defmodule Jidoka.Output.Schema do
  @moduledoc false

  alias Jidoka.Output.{Config, Error}

  @spec normalize_attrs(keyword() | map()) :: {:ok, map()} | {:error, term()}
  def normalize_attrs(attrs) when is_list(attrs) or is_map(attrs) do
    attrs = Map.new(attrs)

    schema =
      Map.get(attrs, :schema) ||
        Map.get(attrs, "schema") ||
        Map.get(attrs, :object_schema) ||
        Map.get(attrs, "object_schema")

    retries = Map.get(attrs, :retries, Map.get(attrs, "retries", Config.default_retries()))

    mode =
      Map.get(attrs, :on_validation_error, Map.get(attrs, "on_validation_error", Config.default_on_validation_error()))

    with {:ok, schema_kind} <- schema_kind(schema),
         {:ok, retries} <- normalize_retries(retries),
         {:ok, mode} <- normalize_mode(mode),
         :ok <- validate_schema_shape(schema, schema_kind) do
      {:ok, %{schema: schema, schema_kind: schema_kind, retries: retries, on_validation_error: mode}}
    end
  end

  @spec validate(map(), term()) :: {:ok, map()} | {:error, term()}
  def validate(%{schema_kind: :zoi, schema: schema}, value) when is_map(value) do
    value = normalize_zoi_input(schema, value)

    case Zoi.parse(schema, value) do
      {:ok, parsed} when is_map(parsed) ->
        {:ok, parsed}

      {:ok, other} ->
        {:error, Error.output_error(:expected_map_result, other, value)}

      {:error, errors} ->
        {:error, Error.output_error({:schema, Zoi.treefy_errors(errors)}, value)}
    end
  end

  def validate(%{schema_kind: :json_schema, schema: schema}, value) when is_map(value) do
    case ReqLLM.Schema.validate(value, schema) do
      {:ok, parsed} when is_map(parsed) ->
        {:ok, parsed}

      {:ok, other} ->
        {:error, Error.output_error(:expected_map_result, other, value)}

      {:error, reason} ->
        {:error, Error.output_error({:schema, Error.reason_message(reason)}, value)}
    end
  end

  def validate(%{}, value), do: {:error, Error.output_error(:expected_map, value)}

  @spec parse(map(), term()) :: {:ok, map()} | {:error, term()}
  def parse(%{} = output, %ReqLLM.Response{} = response) do
    case ReqLLM.Response.unwrap_object(response, json_repair: true) do
      {:ok, object} -> validate(output, object)
      {:error, reason} -> {:error, Error.output_error({:parse, Error.reason_message(reason)}, response)}
    end
  end

  def parse(%{} = output, value) when is_map(value) do
    validate(output, unwrap_object_map(value))
  end

  def parse(%{} = output, value) when is_binary(value) do
    with {:ok, decoded} <- decode_json_object(value) do
      validate(output, decoded)
    end
  end

  def parse(%{}, value), do: {:error, Error.output_error(:unsupported_raw_output, value)}

  @spec instructions(map() | nil) :: String.t() | nil
  def instructions(nil), do: nil

  def instructions(%{} = output) do
    schema_json =
      output
      |> json_schema()
      |> Jason.encode!(pretty: true)

    """
    Structured output:
    Return the final answer as a single JSON object that matches this JSON Schema.
    Do not wrap the JSON in Markdown fences. Do not include explanatory text outside the JSON object.

    #{schema_json}
    """
    |> String.trim()
  end

  @spec json_schema(map()) :: map()
  def json_schema(%{schema_kind: :json_schema, schema: schema}), do: schema
  def json_schema(%{schema_kind: :zoi, schema: schema}), do: ReqLLM.Schema.to_json(schema)

  @spec imported_schema?(term()) :: boolean()
  def imported_schema?(%{} = schema) do
    type = Map.get(schema, "type") || Map.get(schema, :type)
    properties = Map.get(schema, "properties") || Map.get(schema, :properties)
    type in ["object", :object] and is_map(properties)
  end

  def imported_schema?(_schema), do: false

  defp decode_json_object(value) do
    value
    |> strip_markdown_fence()
    |> Jason.decode()
    |> case do
      {:ok, decoded} when is_map(decoded) -> {:ok, decoded}
      {:ok, other} -> {:error, Error.output_error(:expected_map, other)}
      {:error, error} -> {:error, Error.output_error({:parse, Error.reason_message(error)}, value)}
    end
  end

  defp strip_markdown_fence(value) do
    trimmed = String.trim(value)

    case Regex.run(~r/\A```[^\n]*\n?(.*?)\s*```\z/s, trimmed) do
      [_, inner] -> String.trim(inner)
      _other -> trimmed
    end
  end

  defp schema_kind(schema) do
    cond do
      zoi_schema?(schema) -> {:ok, :zoi}
      imported_schema?(schema) -> {:ok, :json_schema}
      true -> {:error, "output schema must be a Zoi object schema or imported JSON object schema"}
    end
  end

  defp validate_schema_shape(schema, :zoi) do
    if Zoi.Type.impl_for(schema) == Zoi.Type.Zoi.Types.Map do
      :ok
    else
      {:error, "output schema must be a Zoi object/map schema"}
    end
  end

  defp validate_schema_shape(schema, :json_schema) do
    if imported_schema?(schema) do
      :ok
    else
      {:error, "imported output schema must be a JSON Schema object with properties"}
    end
  end

  defp normalize_retries(value) when is_integer(value) and value >= 0, do: {:ok, min(value, Config.max_retries())}

  defp normalize_retries(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> normalize_retries(integer)
      _other -> {:error, "output retries must be a non-negative integer"}
    end
  end

  defp normalize_retries(_value), do: {:error, "output retries must be a non-negative integer"}

  defp normalize_mode(value) when value in [:repair, "repair"], do: {:ok, :repair}
  defp normalize_mode(value) when value in [:error, "error"], do: {:ok, :error}
  defp normalize_mode(_value), do: {:error, "output on_validation_error must be :repair or :error"}

  defp zoi_schema?(schema), do: is_struct(schema) and not is_nil(Zoi.Type.impl_for(schema))

  defp normalize_zoi_input(%Zoi.Types.Map{fields: fields}, value) when is_map(value) do
    field_map =
      Map.new(fields, fn {field, _schema} ->
        {to_string(field), field}
      end)

    Map.new(value, fn {key, field_value} ->
      normalized_key =
        if is_binary(key) do
          Map.get(field_map, key, key)
        else
          key
        end

      nested_schema = field_schema(fields, normalized_key)
      {normalized_key, normalize_zoi_input(nested_schema, field_value)}
    end)
  end

  defp normalize_zoi_input(%Zoi.Types.Array{inner: inner}, values) when is_list(values) do
    Enum.map(values, &normalize_zoi_input(inner, &1))
  end

  defp normalize_zoi_input(%Zoi.Types.Enum{enum_type: :atom, values: values}, value) when is_binary(value) do
    Enum.find_value(values, value, fn {_label, atom_value} ->
      if Atom.to_string(atom_value) == value do
        atom_value
      end
    end)
  end

  defp normalize_zoi_input(_schema, value), do: value

  defp field_schema(fields, key) do
    Enum.find_value(fields, fn {field, schema} ->
      if field == key, do: schema
    end)
  end

  defp unwrap_object_map(%{object: object}) when is_map(object), do: object
  defp unwrap_object_map(%{"object" => object}) when is_map(object), do: object
  defp unwrap_object_map(map), do: map
end
