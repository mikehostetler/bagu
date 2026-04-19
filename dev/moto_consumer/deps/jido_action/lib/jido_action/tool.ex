defmodule Jido.Action.Tool do
  @moduledoc """
  Provides functionality to convert Jido Actions into generic tool representations.

  This module allows Jido Actions to be converted into standardized tool maps
  that can be used by various AI integration layers.

  ## Tool Formats

  - `to_tool/1` - Returns a generic tool map with name, description, function, and schema
  - `to_tool/2` - Same as `to_tool/1` with JSON schema options (e.g., strict mode)

  ## Utility Functions

  - `convert_params_using_schema/2` - Normalizes LLM arguments (string keys → atom keys, type coercion)
  - `build_parameters_schema/1` - Converts action schema to JSON Schema format
  - `build_parameters_schema/2` - Same as `build_parameters_schema/1` with schema options
  - `execute_action/3` - Executes an action with schema-based param conversion
  """

  alias Jido.Action.Schema

  @type tool :: %{
          name: String.t(),
          description: String.t(),
          function: (map(), map() -> {:ok, String.t()} | {:error, String.t()}),
          parameters_schema: map()
        }

  @doc """
  Converts a Jido Exec into a tool representation.

  ## Arguments

    * `action` - The module implementing the Jido.Action behavior.

  ## Returns

    A map representing the action as a tool, compatible with systems like LangChain.

  ## Examples

      iex> tool = Jido.Action.Tool.to_tool(MyExec)
      %{
        name: "my_action",
        description: "Performs a specific task",
        function: #Function<...>,
        parameters_schema: %{...}
      }
  """
  @spec to_tool(module()) :: tool()
  def to_tool(action) when is_atom(action), do: to_tool(action, [])

  @spec to_tool(module(), keyword()) :: tool()
  def to_tool(action, opts) when is_atom(action) and is_list(opts) do
    %{
      name: action.name(),
      description: action.description(),
      function: &execute_action(action, &1, &2),
      parameters_schema: build_parameters_schema(action.schema(), opts)
    }
  end

  @doc """
  Executes an action and formats the result for tool output.

  This function is typically used as the function value in the tool representation.
  """
  @spec execute_action(module(), map(), map()) :: {:ok, String.t()} | {:error, String.t()}
  def execute_action(action, params, context) do
    # Convert string keys to atom keys and handle type conversion based on schema
    converted_params = convert_params_using_schema(params, action.schema())
    safe_context = context || %{}

    case Jido.Exec.run(action, converted_params, safe_context) do
      {:ok, result} ->
        {:ok, Jason.encode!(result)}

      {:error, %_{} = error} when is_exception(error) ->
        {:error, Jason.encode!(%{error: inspect(error)})}

      {:error, reason} ->
        {:error, Jason.encode!(%{error: inspect(reason)})}
    end
  end

  @doc """
  Helper function to convert params using schema information.

  Converts string keys to atom keys and handles type conversion based on schema.
  Supports both atom and string input keys, and preserves unknown keys (open validation).
  """
  def convert_params_using_schema(params, schema) when is_map(params) do
    case Schema.schema_type(schema) do
      :json_schema ->
        convert_params_using_json_schema(params, schema)

      _ ->
        schema_keys = Schema.known_keys(schema)
        convert_params_using_known_keys(params, schema, schema_keys)
    end
  end

  defp convert_params_using_json_schema(params, schema) do
    key_pairs =
      schema
      |> Schema.json_schema_known_key_forms()
      |> Enum.flat_map(fn
        %{atom: atom, string: string} when is_atom(atom) and not is_nil(atom) ->
          [{atom, string}]

        _ ->
          []
      end)

    convert_params_using_key_pairs(params, schema, key_pairs)
  end

  defp convert_params_using_known_keys(params, schema, schema_keys) do
    key_pairs = Enum.map(schema_keys, fn key -> {key, to_string(key)} end)
    convert_params_using_key_pairs(params, schema, key_pairs)
  end

  defp convert_params_using_key_pairs(params, schema, key_pairs) do
    {known_converted, unknown_params} =
      Enum.reduce(key_pairs, {%{}, params}, fn {key, string_key}, {known_acc, rest} ->
        {atom_value, rest} = Map.pop(rest, key, :__missing__)

        {value, rest} =
          case atom_value do
            :__missing__ ->
              Map.pop(rest, string_key, :__missing__)

            _ ->
              {_dropped_string_value, rest2} = Map.pop(rest, string_key, :__missing__)
              {atom_value, rest2}
          end

        case value do
          :__missing__ ->
            {known_acc, rest}

          _ ->
            converted_value = convert_value_with_schema(schema, key, value)
            {Map.put(known_acc, key, converted_value), rest}
        end
      end)

    Map.merge(unknown_params, known_converted)
  end

  defp convert_value_with_schema(schema, key, value) when is_list(schema) do
    schema_entry = Keyword.get(schema, key, [])
    type = Keyword.get(schema_entry, :type)
    coerce_value(type, value)
  end

  defp convert_value_with_schema(_schema, _key, value) do
    # For Zoi schemas, let the validation handle conversion
    value
  end

  defp coerce_value(:float, value) when is_binary(value) do
    parse_float(value)
  end

  defp coerce_value(:float, value) when is_integer(value) do
    value * 1.0
  end

  defp coerce_value(:integer, value) when is_binary(value) do
    parse_integer(value)
  end

  defp coerce_value(_type, value), do: value

  defp parse_float(value) do
    case Float.parse(value) do
      {num, _} -> num
      :error -> value
    end
  end

  defp parse_integer(value) do
    case Integer.parse(value) do
      {num, _} -> num
      :error -> value
    end
  end

  @doc """
  Builds a parameters schema for the tool based on the action's schema.

  ## Arguments

    * `schema` - The NimbleOptions or Zoi schema from the action.

  ## Returns

    A map representing the parameters schema in a format compatible with LangChain.
  """
  @spec build_parameters_schema(Schema.t()) :: map()
  def build_parameters_schema(schema), do: build_parameters_schema(schema, [])

  @spec build_parameters_schema(Schema.t(), keyword()) :: map()
  def build_parameters_schema(schema, opts) when is_list(opts),
    do: Schema.to_json_schema(schema, opts)
end
