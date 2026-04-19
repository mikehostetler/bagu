defmodule Jido.Exec.Telemetry do
  @moduledoc """
  Centralized telemetry, logging, and debugging helpers for Jido.Exec.

  This module consolidates all telemetry event emission, logging functionality,
  and error message extraction used throughout the execution system.
  """

  import Jido.Action.Util, only: [cond_log: 3]

  require Logger

  @redacted_value "[REDACTED]"
  @max_depth 4
  @max_collection_items 25
  @max_binary_bytes 256
  @sensitive_patterns [
    "password",
    "passwd",
    "passphrase",
    "secret",
    "token",
    "apikey",
    "accesskey",
    "privatekey",
    "authorization",
    "auth",
    "cookie",
    "session",
    "credential"
  ]
  @inspect_opts [charlists: :as_lists, printable_limit: :infinity, limit: :infinity]

  @doc """
  Emits telemetry start event for action execution.
  """
  @spec emit_start_event(module(), map(), map()) :: :ok
  def emit_start_event(action, params, context) do
    metadata =
      sanitize_value(%{
        action: action,
        params: params,
        context: context
      })

    :telemetry.execute(
      [:jido, :action, :start],
      %{system_time: System.system_time()},
      metadata
    )
  end

  @doc """
  Emits telemetry end event for action execution.
  """
  @spec emit_end_event(module(), map(), map(), any()) :: :ok
  def emit_end_event(action, params, context, result) do
    measurements = %{
      system_time: System.system_time(),
      # Duration would need to be calculated by caller
      duration: 0
    }

    metadata =
      sanitize_value(%{
        action: action,
        params: params,
        context: context,
        result: result
      })

    :telemetry.execute([:jido, :action, :stop], measurements, metadata)
  end

  @doc """
  Logs the start of action execution.
  """
  @spec log_execution_start(module(), map(), map()) :: :ok
  def log_execution_start(action, params, context) do
    Logger.notice(
      "Executing #{inspect(action)} with params: #{safe_inspect(params)} and context: #{safe_inspect(context)}"
    )
  end

  @doc """
  Logs the end of action execution.
  """
  @spec log_execution_end(module(), map(), map(), any()) :: :ok
  def log_execution_end(action, _params, _context, result) do
    case result do
      {:ok, result_data} ->
        Logger.debug(
          "Finished execution of #{inspect(action)}, result: #{safe_inspect(result_data)}"
        )

      {:ok, result_data, directive} ->
        Logger.debug(
          "Finished execution of #{inspect(action)}, result: #{safe_inspect(result_data)}, directive: #{safe_inspect(directive)}"
        )

      {:error, error} ->
        Logger.error("Action #{inspect(action)} failed: #{safe_inspect(error)}")

      {:error, error, directive} ->
        Logger.error(
          "Action #{inspect(action)} failed: #{safe_inspect(error)}, directive: #{safe_inspect(directive)}"
        )

      other ->
        Logger.debug("Finished execution of #{inspect(action)}, result: #{safe_inspect(other)}")
    end
  end

  @doc """
  Safely extracts error messages from various error types, handling nil and nested cases.
  """
  @spec extract_safe_error_message(any()) :: String.t()
  def extract_safe_error_message(error) do
    case error do
      %{message: %{message: inner_message}} when is_binary(inner_message) ->
        inner_message

      %{message: nil} ->
        ""

      %{message: message} when is_binary(message) ->
        message

      %{message: message} when is_struct(message) ->
        if Map.has_key?(message, :message) and is_binary(message.message) do
          message.message
        else
          safe_inspect(message)
        end

      _ ->
        safe_inspect(error)
    end
  end

  @doc """
  Conditional logging wrapper for start events.
  """
  @spec cond_log_start(atom(), module(), map(), map()) :: :ok
  def cond_log_start(log_level, action, params, context) do
    cond_log(
      log_level,
      :notice,
      "Executing #{inspect(action)} with params: #{safe_inspect(params)} and context: #{safe_inspect(context)}"
    )
  end

  @doc """
  Conditional logging wrapper for end events.
  """
  @spec cond_log_end(atom(), module(), any()) :: :ok
  def cond_log_end(log_level, action, result) do
    case result do
      {:ok, result_data} ->
        cond_log(
          log_level,
          :debug,
          "Finished execution of #{inspect(action)}, result: #{safe_inspect(result_data)}"
        )

      {:ok, result_data, directive} ->
        cond_log(
          log_level,
          :debug,
          "Finished execution of #{inspect(action)}, result: #{safe_inspect(result_data)}, directive: #{safe_inspect(directive)}"
        )

      {:error, error} ->
        cond_log(log_level, :error, "Action #{inspect(action)} failed: #{safe_inspect(error)}")

      {:error, error, directive} ->
        cond_log(
          log_level,
          :error,
          "Action #{inspect(action)} failed: #{safe_inspect(error)}, directive: #{safe_inspect(directive)}"
        )

      other ->
        cond_log(
          log_level,
          :debug,
          "Finished execution of #{inspect(action)}, result: #{safe_inspect(other)}"
        )
    end
  end

  @doc """
  Conditional logging wrapper for errors.
  """
  @spec cond_log_error(atom(), module(), any()) :: :ok
  def cond_log_error(log_level, action, error) do
    cond_log(log_level, :error, "Action #{inspect(action)} failed: #{safe_inspect(error)}")
  end

  @doc """
  Conditional logging wrapper for retry attempts.
  """
  @spec cond_log_retry(atom(), module(), non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          :ok
  def cond_log_retry(log_level, action, retry_count, max_retries, backoff) do
    cond_log(
      log_level,
      :info,
      "Retrying #{inspect(action)} (attempt #{retry_count + 1}/#{max_retries}) after #{backoff}ms backoff"
    )
  end

  @doc """
  Conditional logging wrapper for general messages.
  """
  @spec cond_log_message(atom(), atom(), String.t()) :: :ok
  def cond_log_message(log_level, level, message) do
    cond_log(log_level, level, message)
  end

  @doc """
  Conditional logging wrapper for function errors.
  """
  @spec cond_log_function_error(atom(), any()) :: :ok
  def cond_log_function_error(log_level, error) do
    cond_log(
      log_level,
      :warning,
      "Function invocation error in action: #{extract_safe_error_message(error)}"
    )
  end

  @doc """
  Conditional logging wrapper for unexpected errors.
  """
  @spec cond_log_unexpected_error(atom(), any()) :: :ok
  def cond_log_unexpected_error(log_level, error) do
    cond_log(
      log_level,
      :error,
      "Unexpected error in action: #{extract_safe_error_message(error)}"
    )
  end

  @doc """
  Conditional logging wrapper for caught errors.
  """
  @spec cond_log_caught_error(atom(), any()) :: :ok
  def cond_log_caught_error(log_level, reason) do
    cond_log(
      log_level,
      :warning,
      "Caught unexpected throw/exit in action: #{extract_safe_error_message(reason)}"
    )
  end

  @doc """
  Conditional logging wrapper for execution debug.
  """
  @spec cond_log_execution_debug(atom(), module(), map(), map()) :: :ok
  def cond_log_execution_debug(log_level, action, params, context) do
    cond_log(
      log_level,
      :debug,
      "Starting execution of #{inspect(action)}, params: #{safe_inspect(params)}, context: #{safe_inspect(context)}"
    )
  end

  @doc """
  Conditional logging wrapper for validation failures.
  """
  @spec cond_log_validation_failure(atom(), module(), any()) :: :ok
  def cond_log_validation_failure(log_level, action, validation_error) do
    cond_log(
      log_level,
      :error,
      "Action #{inspect(action)} output validation failed: #{safe_inspect(validation_error)}"
    )
  end

  @doc """
  Conditional logging wrapper for general failures.
  """
  @spec cond_log_failure(atom(), String.t()) :: :ok
  def cond_log_failure(log_level, message) do
    cond_log(log_level, :debug, "Action Execution failed: #{message}")
  end

  @doc false
  @spec sanitize_value(any()) :: any()
  def sanitize_value(value), do: do_sanitize(value, 0)

  defp safe_inspect(value) do
    value
    |> sanitize_value()
    |> inspect(@inspect_opts)
  rescue
    _ ->
      value
      |> sanitize_value()
      |> strip_struct_tags()
      |> inspect(@inspect_opts)
  end

  defp do_sanitize(value, depth) when depth >= @max_depth do
    summarize_truncated(value)
  end

  defp do_sanitize(%_{} = struct, depth) when depth + 1 >= @max_depth do
    summarize_truncated_struct(struct)
  end

  defp do_sanitize(%_{} = struct, depth) do
    struct
    |> Map.from_struct()
    |> do_sanitize(depth)
    |> Map.put(:__struct__, inspect(struct.__struct__))
  end

  defp do_sanitize(value, depth) when is_map(value) do
    value
    |> Map.to_list()
    |> Enum.map(fn {key, raw_value} ->
      {sanitize_key(key, depth + 1), key, raw_value}
    end)
    |> Enum.sort_by(fn {sanitized_key, _key, _value} -> inspect(sanitized_key) end)
    |> Enum.split(@max_collection_items)
    |> then(fn {kept, dropped} ->
      sanitized =
        kept
        |> Enum.map(fn {sanitized_key, key, raw_value} ->
          sanitized_value =
            if sensitive_key?(key) do
              @redacted_value
            else
              do_sanitize(raw_value, depth + 1)
            end

          {sanitized_key, sanitized_value}
        end)
        |> Map.new()

      if dropped == [] do
        sanitized
      else
        Map.put(sanitized, :__truncated_fields__, length(dropped))
      end
    end)
  end

  defp do_sanitize(value, depth) when is_list(value) do
    {kept, dropped} = Enum.split(value, @max_collection_items)
    sanitized = Enum.map(kept, &do_sanitize(&1, depth + 1))

    if dropped == [] do
      sanitized
    else
      sanitized ++ [%{__truncated_items__: length(dropped)}]
    end
  end

  defp do_sanitize(value, depth) when is_tuple(value) do
    value
    |> Tuple.to_list()
    |> do_sanitize(depth)
    |> List.to_tuple()
  end

  defp do_sanitize(value, _depth) when is_binary(value) do
    if byte_size(value) > @max_binary_bytes do
      kept = binary_part(value, 0, @max_binary_bytes)
      truncated = byte_size(value) - @max_binary_bytes
      "#{kept}...(truncated #{truncated} bytes)"
    else
      value
    end
  end

  defp do_sanitize(value, _depth), do: value

  defp sensitive_key?(key) when is_atom(key), do: sensitive_key?(Atom.to_string(key))

  defp sensitive_key?(key) when is_binary(key) do
    normalized = key |> String.downcase() |> String.replace(~r/[^a-z0-9]/u, "")
    Enum.any?(@sensitive_patterns, &String.contains?(normalized, &1))
  end

  defp sensitive_key?(key), do: sensitive_key?(inspect(key))

  defp sanitize_key(key, _depth)
       when is_atom(key) or is_binary(key) or is_number(key) or is_boolean(key) or is_nil(key),
       do: key

  defp sanitize_key(key, depth), do: do_sanitize(key, depth)

  defp normalize_struct_marker(mod) when is_atom(mod), do: inspect(mod)
  defp normalize_struct_marker(mod), do: mod

  defp strip_struct_tags(%{__struct__: mod} = map) do
    map
    |> Map.put(:__struct__, normalize_struct_marker(mod))
    |> Map.new(fn {k, v} -> {k, strip_struct_tags(v)} end)
  end

  defp strip_struct_tags(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {k, strip_struct_tags(v)} end)
  end

  defp strip_struct_tags(list) when is_list(list), do: Enum.map(list, &strip_struct_tags/1)
  defp strip_struct_tags(value), do: value

  defp summarize_truncated(%_{} = struct), do: summarize_truncated_struct(struct)

  defp summarize_truncated(value) when is_map(value) do
    %{__truncated_depth__: @max_depth, type: :map, size: map_size(value)}
  end

  defp summarize_truncated(value) when is_list(value) do
    %{__truncated_depth__: @max_depth, type: :list, size: length(value)}
  end

  defp summarize_truncated(value) when is_tuple(value) do
    %{__truncated_depth__: @max_depth, type: :tuple, size: tuple_size(value)}
  end

  defp summarize_truncated(value) when is_binary(value), do: do_sanitize(value, @max_depth - 1)
  defp summarize_truncated(value), do: value

  defp summarize_truncated_struct(struct) do
    %{
      __truncated_depth__: @max_depth,
      type: :struct,
      module: inspect(struct.__struct__),
      size: map_size(struct)
    }
  end
end
