defmodule Jidoka.Output.Error do
  @moduledoc false

  alias Jidoka.Output.Config

  @spec raw_preview(term()) :: String.t()
  def raw_preview(value), do: Jidoka.Sanitize.preview(value, Config.raw_preview_bytes())

  @spec output_error(term(), term()) :: term()
  def output_error(:expected_map, value), do: output_error(:expected_map, value, value)
  def output_error(:unsupported_raw_output, value), do: output_error(:unsupported_raw_output, value, value)
  def output_error({:parse, message}, value), do: output_error({:parse, message}, value, value)
  def output_error({:schema, errors}, value), do: output_error({:schema, errors}, value, value)
  def output_error(:missing_repair_model, value), do: output_error(:missing_repair_model, value, value)
  def output_error({:repair_failed, message}, value), do: output_error({:repair_failed, message}, value, value)
  def output_error({:repair_exception, message}, value), do: output_error({:repair_exception, message}, value, value)

  @spec output_error(term(), term(), term()) :: term()
  def output_error(reason, value, raw) do
    Jidoka.Error.validation_error(output_error_message(reason),
      field: :output,
      value: value,
      details: %{reason: reason, raw_preview: raw_preview(raw)}
    )
  end

  @spec reason_message(term()) :: String.t()
  def reason_message(%{__exception__: true} = error), do: Exception.message(error)
  def reason_message(reason), do: inspect(reason, limit: 20, printable_limit: Config.raw_preview_bytes())

  defp output_error_message(:expected_map), do: "Invalid output: expected a JSON object."
  defp output_error_message(:expected_map_result), do: "Invalid output schema: expected parsing to return a map."
  defp output_error_message(:unsupported_raw_output), do: "Invalid output: unsupported model response shape."
  defp output_error_message(:missing_repair_model), do: "Invalid output: cannot repair without a model."
  defp output_error_message({:parse, message}), do: "Invalid output: could not parse JSON object. #{message}"

  defp output_error_message({:schema, errors}),
    do: "Invalid output: output did not match the configured schema. #{inspect(errors)}"

  defp output_error_message({:repair_failed, message}), do: "Invalid output repair failed. #{message}"
  defp output_error_message({:repair_exception, message}), do: "Invalid output repair failed. #{message}"
end
