defmodule Jido.Action.Runtime do
  @moduledoc """
  Runtime validation helpers used by generated `Jido.Action` modules.

  This module applies action lifecycle hooks around parameter and output
  validation, preserving unknown keys so composable action chains can pass
  through additional data.
  """

  alias Jido.Action.Schema

  @doc """
  Validates action input parameters with lifecycle hooks.

  Runs `on_before_validate_params/1`, validates only known schema keys,
  preserves unknown keys, then runs `on_after_validate_params/1`.
  """
  @spec validate_params(map(), module()) :: {:ok, map()} | {:error, any()}
  def validate_params(params, module) do
    with {:ok, params} <- module.on_before_validate_params(params),
         {:ok, validated_params} <- do_validate_params(params, module) do
      module.on_after_validate_params(validated_params)
    end
  end

  @doc """
  Validates action output with lifecycle hooks.

  Runs `on_before_validate_output/1`, validates only known output schema keys,
  preserves unknown keys, then runs `on_after_validate_output/1`.
  """
  @spec validate_output(map(), module()) :: {:ok, map()} | {:error, any()}
  def validate_output(output, module) do
    with {:ok, output} <- module.on_before_validate_output(output),
         {:ok, validated_output} <- do_validate_output(output, module) do
      module.on_after_validate_output(validated_output)
    end
  end

  defp do_validate_params(params, module) do
    param_schema = module.schema()
    {known_params, unknown_params} = split_known_and_unknown(params, param_schema)

    param_schema
    |> Schema.validate(known_params)
    |> handle_validation_result(unknown_params, "Action", module)
  end

  defp do_validate_output(output, module) do
    out_schema = module.output_schema()
    {known_output, unknown_output} = split_known_and_unknown(output, out_schema)

    out_schema
    |> Schema.validate(known_output)
    |> handle_validation_result(unknown_output, "Action output", module)
  end

  defp handle_validation_result({:ok, validated}, unknown, _error_context, _module) do
    validated_map = struct_to_map(validated)
    {:ok, Map.merge(unknown, validated_map)}
  end

  defp handle_validation_result({:error, error}, _unknown, error_context, module) do
    error
    |> Schema.format_error(error_context, module)
    |> then(&{:error, &1})
  end

  defp split_known_and_unknown(data, schema) do
    case Schema.schema_type(schema) do
      :json_schema ->
        known_keys =
          schema
          |> Schema.json_schema_known_key_forms()
          |> Enum.flat_map(fn
            %{atom: atom, string: string} when is_atom(atom) and not is_nil(atom) ->
              [atom, string]

            %{string: string} ->
              [string]
          end)
          |> Enum.uniq()

        Map.split(data, known_keys)

      _ ->
        known_keys = Schema.known_keys(schema)
        Map.split(data, known_keys)
    end
  end

  defp struct_to_map(value) when is_struct(value), do: Map.from_struct(value)
  defp struct_to_map(value), do: value
end
