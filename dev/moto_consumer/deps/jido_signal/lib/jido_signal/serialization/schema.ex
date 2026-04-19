defmodule Jido.Signal.Serialization.Schema do
  @moduledoc """
  Schema validation for Jido Signals using Zoi.

  Provides CloudEvents-compliant schema validation with structured error messages.
  """

  @doc """
  Returns the Zoi schema for validating Signal structures.

  The schema enforces CloudEvents required fields and validates common optional fields.
  CloudEvents extensions (additional fields) are allowed by default.
  """
  @spec signal_schema() :: term()
  def signal_schema do
    Zoi.object(
      %{
        "type" => Zoi.string() |> Zoi.min(1),
        "source" => Zoi.string() |> Zoi.min(1),
        "id" => Zoi.optional(Zoi.string()),
        "specversion" => Zoi.optional(Zoi.string()),
        "datacontenttype" => Zoi.optional(Zoi.string()),
        "dataschema" => Zoi.optional(Zoi.string()),
        "subject" => Zoi.optional(Zoi.string()),
        "time" => Zoi.optional(Zoi.string()),
        "data" => Zoi.optional(Zoi.map()),
        "data_base64" => Zoi.optional(Zoi.string()),
        "extensions" => Zoi.optional(Zoi.map()),
        "jido_schema_version" => Zoi.optional(Zoi.integer())
      },
      unrecognized_keys: :strip
    )
  end

  @doc """
  Validates a map against the Signal schema.

  Returns `{:ok, valid_map}` if valid, or `{:error, errors}` with structured error details.

  ## Examples

      iex> Schema.validate_signal(%{"type" => "test", "source" => "/test"})
      {:ok, %{"type" => "test", "source" => "/test"}}

      iex> Schema.validate_signal(%{"type" => "", "source" => "/test"})
      {:error, %{"type" => ["type cannot be empty"]}}
  """
  @spec validate_signal(map()) :: {:ok, map()} | {:error, map()}
  def validate_signal(map) when is_map(map) do
    case Zoi.parse(signal_schema(), map) do
      {:ok, valid} ->
        {:ok, valid}

      {:error, errors} when is_list(errors) ->
        {:error, format_zoi_errors(errors)}
    end
  end

  @doc """
  Generates a JSON Schema representation of the Signal schema.

  Useful for API documentation and OpenAPI specifications.

  ## Examples

      iex> json_schema = Schema.to_json_schema()
      iex> json_schema["type"]
      :object
  """
  @spec to_json_schema() :: map()
  def to_json_schema do
    Zoi.to_json_schema(signal_schema())
  end

  defp format_zoi_errors(errors) when is_list(errors) do
    Enum.reduce(errors, %{}, fn %Zoi.Error{} = error, acc ->
      path = format_path(error.path)
      message = error.message
      Map.update(acc, path, [message], &[message | &1])
    end)
  end

  defp format_path([]), do: "_root"

  defp format_path(path) when is_list(path) do
    path
    |> Enum.map_join(".", &to_string/1)
  end

  defp format_path(path), do: to_string(path)
end
