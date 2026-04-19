defmodule Jido.Action.Error do
  @moduledoc """
  Centralized error handling for Jido Actions using Splode.

  This module provides a consistent way to create, aggregate, and handle errors
  within the Jido Action system. It uses the Splode library to enable error
  composition and classification.

  ## Structure & Naming

  This module has two kinds of submodules:

  * **Error classes** (for Splode): `Invalid`, `Execution`, `Config`, `Internal`.
    These are used internally by Splode for classification and aggregation.
    You generally should not raise or pattern match on these modules directly.

  * **Concrete exception structs** (ending in `Error`): `InvalidInputError`,
    `ExecutionFailureError`, `TimeoutError`, `ConfigurationError`, `InternalError`.
    These are the types you raise, rescue, and pattern match in application code.

  For cross-package handling, use `Jido.Error.to_map/1` and match on the
  normalized `:type` atom (e.g. `:timeout`, `:validation_error`, `:execution_error`).

  ## Error Classes

  Errors are organized into the following classes, in order of precedence:

  - `:invalid` - Input validation, bad requests, and invalid configurations
  - `:execution` - Runtime execution errors and action failures
  - `:config` - System configuration and setup errors
  - `:internal` - Unexpected internal errors and system failures

  When multiple errors are aggregated, the class of the highest precedence error
  determines the overall error class.

  ## Usage

  Use this module to create and handle errors consistently:

      # Create a specific error
      {:error, error} = Jido.Action.Error.validation_error("must be a positive integer", field: :user_id)

      # Create timeout error
      {:error, timeout} = Jido.Action.Error.timeout_error("Action timed out after 30s", timeout: 30000)

      # Convert any value to a proper error
      {:error, normalized} = Jido.Action.Error.to_error("Something went wrong")
  """
  use Splode,
    # Error class modules for Splode
    error_classes: [
      invalid: Invalid,
      execution: Execution,
      config: Config,
      internal: Internal
    ],
    unknown_error: __MODULE__.Internal.UnknownError

  # Error class modules for Splode - these are for classification/aggregation only.
  # Use the concrete exception structs (ending in `Error`) for raising/matching.

  defmodule Invalid do
    @moduledoc """
    Invalid input error class for Splode.

    This module is used by Splode to classify invalid-input errors when
    aggregating or analyzing multiple errors. Do not raise or match on this
    module directly — use `Jido.Action.Error.InvalidInputError` and helpers like
    `validation_error/2` instead.
    """
    use Splode.ErrorClass, class: :invalid
  end

  defmodule Execution do
    @moduledoc """
    Execution error class for Splode.

    This module is used by Splode to classify execution-related errors when
    aggregating or analyzing multiple errors. Do not raise or match on this
    module directly — use `Jido.Action.Error.ExecutionFailureError` and helpers like
    `execution_error/2` instead.
    """
    use Splode.ErrorClass, class: :execution
  end

  defmodule Config do
    @moduledoc """
    Configuration error class for Splode.

    This module is used by Splode to classify configuration-related errors when
    aggregating or analyzing multiple errors. Do not raise or match on this
    module directly — use `Jido.Action.Error.ConfigurationError` and helpers like
    `config_error/2` instead.
    """
    use Splode.ErrorClass, class: :config
  end

  defmodule Internal do
    @moduledoc """
    Internal error class for Splode.

    This module is used by Splode to classify internal/unexpected errors when
    aggregating or analyzing multiple errors. Do not raise or match on this
    module directly — use `Jido.Action.Error.InternalError` and helpers like
    `internal_error/2` instead.
    """
    use Splode.ErrorClass, class: :internal

    defmodule UnknownError do
      @moduledoc false
      # This module exists only to satisfy Splode's unknown_error requirement.
      defexception [:message, :details]

      @type t :: %__MODULE__{
              message: String.t(),
              details: map()
            }

      @impl true
      def exception(opts) do
        %__MODULE__{
          message: Keyword.get(opts, :message, "Unknown error"),
          details: Keyword.get(opts, :details, %{})
        }
      end
    end
  end

  # Define specific error structs inline
  defmodule InvalidInputError do
    @moduledoc "Error for invalid input parameters"
    defexception [:message, :field, :value, :details]

    @type t :: %__MODULE__{
            message: String.t(),
            field: atom() | nil,
            value: any() | nil,
            details: map()
          }

    @impl true
    def exception(opts) do
      message = Keyword.get(opts, :message, "Invalid input")

      %__MODULE__{
        message: message,
        field: Keyword.get(opts, :field),
        value: Keyword.get(opts, :value),
        details: Keyword.get(opts, :details, %{})
      }
    end
  end

  defmodule ExecutionFailureError do
    @moduledoc "Error for runtime execution failures"
    defexception [:message, :details]

    @type t :: %__MODULE__{
            message: String.t(),
            details: map()
          }

    @impl true
    def exception(opts) do
      %__MODULE__{
        message: Keyword.get(opts, :message, "Execution failed"),
        details: Keyword.get(opts, :details, %{})
      }
    end
  end

  defmodule TimeoutError do
    @moduledoc "Error for action timeouts"
    defexception [:message, :timeout, :details]

    @type t :: %__MODULE__{
            message: String.t(),
            timeout: non_neg_integer() | nil,
            details: map()
          }

    @impl true
    def exception(opts) do
      %__MODULE__{
        message: Keyword.get(opts, :message, "Action timed out"),
        timeout: Keyword.get(opts, :timeout),
        details: Keyword.get(opts, :details, %{})
      }
    end
  end

  defmodule ConfigurationError do
    @moduledoc "Error for configuration issues"
    defexception [:message, :details]

    @type t :: %__MODULE__{
            message: String.t(),
            details: map()
          }

    @impl true
    def exception(opts) do
      %__MODULE__{
        message: Keyword.get(opts, :message, "Configuration error"),
        details: Keyword.get(opts, :details, %{})
      }
    end
  end

  defmodule InternalError do
    @moduledoc "Error for unexpected internal failures"
    defexception [:message, :details]

    @type t :: %__MODULE__{
            message: String.t(),
            details: map()
          }

    @impl true
    def exception(opts) do
      %__MODULE__{
        message: Keyword.get(opts, :message, "Internal error"),
        details: Keyword.get(opts, :details, %{})
      }
    end
  end

  @doc """
  Creates a validation error for invalid input parameters.
  """
  @spec validation_error(String.t(), map()) :: InvalidInputError.t()
  def validation_error(message, details \\ %{}) do
    InvalidInputError.exception(
      message: message,
      field: details[:field],
      value: details[:value],
      details: details
    )
  end

  @doc """
  Creates an execution error for runtime failures.
  """
  @spec execution_error(String.t(), map()) :: ExecutionFailureError.t()
  def execution_error(message, details \\ %{}) do
    ExecutionFailureError.exception(
      message: message,
      details: details
    )
  end

  @doc """
  Creates a configuration error.
  """
  @spec config_error(String.t(), map()) :: ConfigurationError.t()
  def config_error(message, details \\ %{}) do
    ConfigurationError.exception(
      message: message,
      details: details
    )
  end

  @doc """
  Creates a timeout error.
  """
  @spec timeout_error(String.t(), map()) :: TimeoutError.t()
  def timeout_error(message, details \\ %{}) do
    TimeoutError.exception(
      message: message,
      timeout: details[:timeout],
      details: details
    )
  end

  @doc """
  Creates an internal server error.
  """
  @spec internal_error(String.t(), map()) :: InternalError.t()
  def internal_error(message, details \\ %{}) do
    InternalError.exception(
      message: message,
      details: details
    )
  end

  @type error_map :: %{
          type: atom(),
          message: String.t(),
          details: map(),
          retryable?: boolean()
        }

  @doc """
  Converts action-layer errors into a normalized plain map representation.

  This preserves the action error type and message while exposing a stable,
  serializable shape that downstream packages can adapt to their own domains.
  """
  @spec to_map(term()) :: error_map()
  def to_map({:error, reason, _effects}), do: to_map(reason)
  def to_map({:error, reason}), do: to_map(reason)

  def to_map(%{type: type, message: message} = error) when is_atom(type) do
    %{
      type: type,
      message: normalize_message(message),
      details: normalize_details(Map.get(error, :details, %{})),
      retryable?: normalize_retryable(error, type)
    }
  end

  def to_map(%{code: type, message: message} = error) when is_atom(type) do
    %{
      type: type,
      message: normalize_message(message),
      details: normalize_details(Map.get(error, :details, %{})),
      retryable?: normalize_retryable(error, type)
    }
  end

  def to_map(%InvalidInputError{} = error) do
    %{
      type: :validation_error,
      message: normalize_message(error.message),
      details:
        error.details
        |> normalize_details()
        |> maybe_put(:field, error.field)
        |> maybe_put(:value, error.value),
      retryable?: false
    }
  end

  def to_map(%ExecutionFailureError{} = error) do
    %{
      type: :execution_error,
      message: normalize_message(error.message),
      details: normalize_details(error.details),
      retryable?: normalize_retryable(error.details, :execution_error)
    }
  end

  def to_map(%TimeoutError{} = error) do
    %{
      type: :timeout,
      message: normalize_message(error.message),
      details:
        error.details
        |> normalize_details()
        |> maybe_put(:timeout, error.timeout),
      retryable?: true
    }
  end

  def to_map(%ConfigurationError{} = error) do
    %{
      type: :configuration_error,
      message: normalize_message(error.message),
      details: normalize_details(error.details),
      retryable?: false
    }
  end

  def to_map(%InternalError{} = error) do
    %{
      type: :internal_error,
      message: normalize_message(error.message),
      details: normalize_details(error.details),
      retryable?: false
    }
  end

  def to_map(%Internal.UnknownError{} = error) do
    %{
      type: :internal_error,
      message: normalize_message(error.message),
      details: normalize_details(error.details),
      retryable?: false
    }
  end

  def to_map(%{message: message} = error) when not is_nil(message) do
    %{
      type: :execution_error,
      message: normalize_message(message),
      details:
        error
        |> Map.from_struct()
        |> Map.drop([:__exception__, :message])
        |> normalize_details(),
      retryable?: normalize_retryable(error, :execution_error)
    }
  end

  def to_map(reason) when is_atom(reason) do
    %{
      type: reason,
      message: normalize_message(reason),
      details: %{},
      retryable?: retryable?(reason)
    }
  end

  def to_map(reason) do
    %{
      type: :execution_error,
      message: normalize_message(reason),
      details: %{},
      retryable?: false
    }
  end

  @doc """
  Returns whether the given action-layer error should be considered retryable.

  This mirrors execution-engine retry behavior so downstream packages can make
  the same decision without duplicating action-specific heuristics.
  """
  @spec retryable?(term()) :: boolean()
  def retryable?({:error, reason, _effects}), do: retryable?(reason)
  def retryable?({:error, reason}), do: retryable?(reason)
  def retryable?(%InvalidInputError{}), do: false
  def retryable?(%ConfigurationError{}), do: false
  def retryable?(%TimeoutError{}), do: true
  def retryable?(%ExecutionFailureError{details: details}), do: retryable_hint(details, true)
  def retryable?(%InternalError{details: details}), do: retryable_hint(details, true)
  def retryable?(%Internal.UnknownError{details: details}), do: retryable_hint(details, true)

  def retryable?(%{retryable?: value}) when is_boolean(value), do: value
  def retryable?(%{retryable: value}) when is_boolean(value), do: value

  def retryable?(%{type: type} = error) when is_atom(type) do
    retryable_hint(Map.get(error, :details, error), default_retryable?(type))
  end

  def retryable?(%{code: type} = error) when is_atom(type) do
    retryable_hint(Map.get(error, :details, error), default_retryable?(type))
  end

  def retryable?(%{} = map) do
    retryable_hint(map, true)
  end

  def retryable?(reason) when is_atom(reason), do: default_retryable?(reason)
  def retryable?(_reason), do: true

  @doc """
  Formats a NimbleOptions configuration error for display.
  Used when configuration validation fails during compilation.
  """
  @spec format_nimble_config_error(
          NimbleOptions.ValidationError.t() | any(),
          String.t(),
          module()
        ) ::
          String.t()
  def format_nimble_config_error(
        %NimbleOptions.ValidationError{keys_path: [], message: message},
        module_type,
        module
      ) do
    "Invalid configuration given to use Jido.#{module_type} (#{module}): #{message}"
  end

  def format_nimble_config_error(
        %NimbleOptions.ValidationError{keys_path: keys_path, message: message},
        module_type,
        module
      ) do
    "Invalid configuration given to use Jido.#{module_type} (#{module}) for key #{inspect(keys_path)}: #{message}"
  end

  def format_nimble_config_error(error, _module_type, _module) when is_binary(error), do: error
  def format_nimble_config_error(error, _module_type, _module), do: inspect(error)

  @doc """
  Formats a NimbleOptions validation error for parameter validation.
  Used when validating runtime parameters.
  """
  @spec format_nimble_validation_error(
          NimbleOptions.ValidationError.t() | any(),
          String.t(),
          module()
        ) ::
          String.t()
  def format_nimble_validation_error(
        %NimbleOptions.ValidationError{keys_path: [], message: message},
        module_type,
        module
      ) do
    "Invalid parameters for #{module_type} (#{module}): #{message}"
  end

  def format_nimble_validation_error(
        %NimbleOptions.ValidationError{keys_path: keys_path, message: message},
        module_type,
        module
      ) do
    "Invalid parameters for #{module_type} (#{module}) at #{inspect(keys_path)}: #{message}"
  end

  def format_nimble_validation_error(error, _module_type, _module) when is_binary(error),
    do: error

  def format_nimble_validation_error(error, _module_type, _module), do: inspect(error)

  defp normalize_retryable(error, type) do
    cond do
      is_boolean(Map.get(error, :retryable?)) -> Map.get(error, :retryable?)
      is_boolean(Map.get(error, :retryable)) -> Map.get(error, :retryable)
      true -> retryable_hint(Map.get(error, :details, error), default_retryable?(type))
    end
  end

  defp normalize_message(message) when is_binary(message), do: message
  defp normalize_message(message) when is_atom(message), do: Atom.to_string(message)
  defp normalize_message(message), do: inspect(message)

  defp normalize_details(details) when is_map(details), do: details
  defp normalize_details(_details), do: %{}

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp default_retryable?(type) when type in [:validation_error, :configuration_error], do: false
  defp default_retryable?(_type), do: true

  defp retryable_hint(term, default) do
    case extract_retry_hint(term) do
      nil -> default
      value -> value != false
    end
  end

  defp extract_retry_hint(%{details: details}) do
    case extract_retry_value(details) do
      nil -> details |> extract_nested_reason() |> extract_retry_hint()
      value -> value
    end
  end

  defp extract_retry_hint(%{} = map) do
    case extract_retry_value(map) do
      nil -> map |> extract_nested_reason() |> extract_retry_hint()
      value -> value
    end
  end

  defp extract_retry_hint(_), do: nil

  defp extract_nested_reason(%{} = map) do
    Map.get(map, :reason) || Map.get(map, "reason")
  end

  defp extract_nested_reason(_), do: nil

  defp extract_retry_value(%{} = map) do
    cond do
      Map.has_key?(map, :retry) -> Map.get(map, :retry)
      Map.has_key?(map, "retry") -> Map.get(map, "retry")
      true -> nil
    end
  end

  defp extract_retry_value(keyword) when is_list(keyword) do
    if Keyword.keyword?(keyword), do: Keyword.get(keyword, :retry), else: nil
  end

  defp extract_retry_value(_), do: nil
end
