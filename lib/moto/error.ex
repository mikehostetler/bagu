defmodule Moto.Error do
  @moduledoc """
  Structured Moto error helpers.

  Moto still returns simple tagged tuples at most public boundaries while the API
  is experimental. This module provides the package-level Splode error root used
  when errors need to be raised, normalized, or classified consistently.
  """

  defmodule Invalid do
    @moduledoc "Invalid input error class for Splode."
    use Splode.ErrorClass, class: :invalid
  end

  defmodule Execution do
    @moduledoc "Runtime execution error class for Splode."
    use Splode.ErrorClass, class: :execution
  end

  defmodule Config do
    @moduledoc "Configuration error class for Splode."
    use Splode.ErrorClass, class: :config
  end

  defmodule Internal do
    @moduledoc "Internal error class for Splode."
    use Splode.ErrorClass, class: :internal

    defmodule UnknownError do
      @moduledoc false
      use Splode.Error, class: :internal, fields: [:message, :details, :error]

      @impl true
      def exception(opts) do
        opts = if is_map(opts), do: Map.to_list(opts), else: opts
        message = Keyword.get(opts, :message) || unknown_message(opts[:error])

        opts
        |> Keyword.put(:message, message)
        |> Keyword.put_new(:details, %{})
        |> super()
      end

      defp unknown_message(error) when is_binary(error), do: error
      defp unknown_message(nil), do: "Unknown Moto error"
      defp unknown_message(error), do: inspect(error)
    end
  end

  use Splode,
    error_classes: [
      invalid: Invalid,
      execution: Execution,
      config: Config,
      internal: Internal
    ],
    unknown_error: Internal.UnknownError

  defmodule ValidationError do
    @moduledoc "Invalid input or schema validation error."
    use Splode.Error, class: :invalid, fields: [:message, :field, :value, :details]

    @impl true
    def exception(opts) do
      opts = if is_map(opts), do: Map.to_list(opts), else: opts

      opts
      |> Keyword.put_new(:message, "Invalid Moto input")
      |> Keyword.put_new(:details, %{})
      |> super()
    end
  end

  defmodule ConfigError do
    @moduledoc "Invalid Moto configuration error."
    use Splode.Error, class: :config, fields: [:message, :field, :value, :details]

    @impl true
    def exception(opts) do
      opts = if is_map(opts), do: Map.to_list(opts), else: opts

      opts
      |> Keyword.put_new(:message, "Invalid Moto configuration")
      |> Keyword.put_new(:details, %{})
      |> super()
    end
  end

  defmodule ExecutionError do
    @moduledoc "Moto runtime execution error."
    use Splode.Error, class: :execution, fields: [:message, :phase, :details]

    @impl true
    def exception(opts) do
      opts = if is_map(opts), do: Map.to_list(opts), else: opts

      opts
      |> Keyword.put_new(:message, "Moto execution failed")
      |> Keyword.put_new(:details, %{})
      |> super()
    end
  end

  @doc """
  Builds a validation error with a consistent Moto shape.
  """
  @spec validation_error(String.t(), keyword() | map()) :: Exception.t()
  def validation_error(message, details \\ %{}) do
    ValidationError.exception(put_details(details, message))
  end

  @doc """
  Builds a configuration error with a consistent Moto shape.
  """
  @spec config_error(String.t(), keyword() | map()) :: Exception.t()
  def config_error(message, details \\ %{}) do
    ConfigError.exception(put_details(details, message))
  end

  @doc """
  Builds a runtime execution error with a consistent Moto shape.
  """
  @spec execution_error(String.t(), keyword() | map()) :: Exception.t()
  def execution_error(message, details \\ %{}) do
    ExecutionError.exception(put_details(details, message))
  end

  defp put_details(details, message) when is_map(details) do
    details
    |> Map.put(:message, message)
    |> Map.put_new(:details, %{})
  end

  defp put_details(details, message) when is_list(details) do
    details
    |> Keyword.put(:message, message)
    |> Keyword.put_new(:details, %{})
  end
end
