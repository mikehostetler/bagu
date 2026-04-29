defmodule Jidoka.Error.Normalize.Common do
  @moduledoc false

  alias Jidoka.Error
  alias Jidoka.Error.Normalize.Context

  @type context :: Context.context()

  @spec validation(String.t(), atom(), term(), context()) :: Exception.t()
  def validation(message, field, reason, context) do
    Error.validation_error(message,
      field: field,
      value: Context.detail(context, :value),
      details: Context.details(context, %{cause: reason})
    )
  end

  @spec passthrough_or_validation(Exception.t(), String.t(), atom(), context()) :: Exception.t()
  def passthrough_or_validation(error, message, field, context) do
    if Context.jidoka_error?(error) do
      error
    else
      validation(message, field, error, context)
    end
  end

  @spec passthrough_or_execution(Exception.t(), String.t(), atom(), context()) :: Exception.t()
  def passthrough_or_execution(error, message, phase, context) do
    if Context.jidoka_error?(error) do
      error
    else
      execution(message, phase, error, context)
    end
  end

  @spec memory_exception_error(atom(), Exception.t(), context()) :: Exception.t()
  def memory_exception_error(:retrieve, error, context) do
    execution("Jidoka memory retrieval failed.", :memory, error, context, %{phase: :memory_retrieve})
  end

  def memory_exception_error(:capture, error, context) do
    execution("Jidoka memory capture failed.", :memory, error, context, %{phase: :memory_capture})
  end

  def memory_exception_error(phase, error, context) do
    execution("Jidoka memory failed.", :memory, error, context, %{phase: phase})
  end

  @spec execution(String.t(), atom(), term(), context(), map()) :: Exception.t()
  def execution(message, phase, reason, context, extra \\ %{}) do
    Error.execution_error(message,
      phase: phase,
      details: Context.details(context, Map.merge(%{operation: phase, cause: reason}, extra))
    )
  end

  @spec timeout_error(atom(), term(), context()) :: Exception.t()
  def timeout_error(operation, timeout, context) do
    Error.execution_error("#{humanize(operation)} timed out.",
      phase: operation,
      details:
        Context.details(context, %{
          operation: operation,
          reason: :timeout,
          timeout: timeout,
          cause: {:timeout, timeout}
        })
    )
  end

  defp humanize(operation) do
    operation
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end
end
