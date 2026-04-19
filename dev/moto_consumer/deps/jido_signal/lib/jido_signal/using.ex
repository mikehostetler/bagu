defmodule Jido.Signal.Using do
  @moduledoc """
  Helper module containing macro code for `use Jido.Signal`.

  This module provides the `define_signal_functions/0` macro that generates
  all the necessary functions for a custom Signal module, including:

  - Accessor functions (`type/0`, `default_source/0`, etc.)
  - Constructor functions (`new/0`, `new/1`, `new/2`, `new!/0`, `new!/1`, `new!/2`)
  - Validation functions (`validate_data/1`)
  - Serialization helpers (`to_json/0`, `__signal_metadata__/0`)
  """

  alias __MODULE__, as: Using
  alias Jido.Signal.Error
  alias Jido.Signal.ID

  # Alias for internal use in macros
  @doc """
  Defines all signal-related functions in the calling module.

  This macro is called from `use Jido.Signal` and expects the `@validated_opts`
  module attribute to be set with the validated configuration options.
  """
  defmacro define_signal_functions do
    quote location: :keep do
      alias Jido.Signal.Using

      require Using

      Using.define_accessor_functions()
      Using.define_constructor_functions()
      Using.define_validation_functions()
      Using.define_signal_builder_functions()
      Using.define_caller_module_functions()
    end
  end

  @doc false
  defmacro define_accessor_functions do
    quote location: :keep do
      def type, do: @validated_opts[:type]
      def default_source, do: @validated_opts[:default_source]
      def datacontenttype, do: @validated_opts[:datacontenttype]
      def dataschema, do: @validated_opts[:dataschema]
      def schema, do: @validated_opts[:schema]
      def extension_policy, do: @validated_opts[:extension_policy]

      def to_json do
        %{
          datacontenttype: @validated_opts[:datacontenttype],
          dataschema: @validated_opts[:dataschema],
          default_source: @validated_opts[:default_source],
          extension_policy: @validated_opts[:extension_policy],
          schema: @validated_opts[:schema],
          type: @validated_opts[:type]
        }
      end

      def __signal_metadata__ do
        to_json()
      end
    end
  end

  @doc false
  defmacro define_constructor_functions do
    quote location: :keep do
      @doc """
      Creates a new Signal instance with the configured type and validated data.

      ## Parameters

      - `data`: A map containing the Signal's data payload.
      - `opts`: Additional Signal options (source, subject, etc.)

      ## Returns

      `{:ok, Signal.t()}` if the data is valid, `{:error, String.t()}` otherwise.

      ## Example

          MySignal.new(valid_data, source: "/custom")
          # => {:ok, signal} where signal.type == MySignal.type()

      """
      @spec new(map(), keyword()) :: {:ok, Jido.Signal.t()} | {:error, String.t()}
      def new(data \\ %{}, opts \\ []) do
        with {:ok, validated_data} <- validate_data(data),
             {:ok, signal_attrs} <- build_signal_attrs(validated_data, opts) do
          Jido.Signal.from_map(signal_attrs)
        end
      end

      @doc """
      Creates a new Signal instance, raising an error if invalid.

      ## Parameters

      - `data`: A map containing the Signal's data payload.
      - `opts`: Additional Signal options (source, subject, etc.)

      ## Returns

      `Signal.t()` if the data is valid.

      ## Raises

      `RuntimeError` if the data is invalid.

      ## Example

          MySignal.new!(valid_data, source: "/custom")
          # => %Jido.Signal{} with type MySignal.type()

      """
      @spec new!(map(), keyword()) :: Jido.Signal.t() | no_return()
      def new!(data \\ %{}, opts \\ []) do
        case new(data, opts) do
          {:ok, signal} -> signal
          {:error, reason} -> raise reason
        end
      end
    end
  end

  @doc false
  defmacro define_validation_functions do
    quote location: :keep do
      alias Jido.Signal.Error

      @doc """
      Validates the data for the Signal according to its schema.

      ## Example

          MySignal.validate_data(candidate_data)
          # => {:ok, validated_data} | {:error, reason}

      """
      @spec validate_data(map()) :: {:ok, map()} | {:error, String.t()}
      def validate_data(data) do
        do_validate_data(@validated_opts[:schema], data)
      end

      defp do_validate_data([], data), do: {:ok, data}

      defp do_validate_data(schema, data) when is_list(schema) do
        case NimbleOptions.validate(Enum.to_list(data), schema) do
          {:ok, validated_data} ->
            {:ok, Map.new(validated_data)}

          {:error, %NimbleOptions.ValidationError{} = error} ->
            reason = Error.format_nimble_validation_error(error, "Signal", __MODULE__)
            {:error, reason}
        end
      end
    end
  end

  @doc false
  defmacro define_signal_builder_functions do
    quote location: :keep do
      alias Jido.Signal.Ext
      alias Jido.Signal.ID

      defp build_signal_attrs(validated_data, opts) do
        caller = get_caller_module()

        attrs =
          build_base_attrs(validated_data, caller)
          |> maybe_add_datacontenttype()
          |> maybe_add_dataschema()
          |> apply_user_options(opts)

        normalize_policy_extensions(attrs)
      end

      defp build_base_attrs(validated_data, caller) do
        %{
          "data" => validated_data,
          "id" => ID.generate!(),
          "source" => @validated_opts[:default_source] || caller,
          "specversion" => "1.0.2",
          "time" => DateTime.utc_now() |> DateTime.to_iso8601(),
          "type" => @validated_opts[:type]
        }
      end

      defp maybe_add_datacontenttype(attrs) do
        add_optional_attr(attrs, "datacontenttype", @validated_opts[:datacontenttype])
      end

      defp maybe_add_dataschema(attrs) do
        add_optional_attr(attrs, "dataschema", @validated_opts[:dataschema])
      end

      defp add_optional_attr(attrs, _key, nil), do: attrs
      defp add_optional_attr(attrs, key, value), do: Map.put(attrs, key, value)

      defp apply_user_options(attrs, opts) do
        Enum.reduce(opts, attrs, fn {key, value}, acc ->
          Map.put(acc, to_string(key), value)
        end)
      end

      defp normalize_policy_extensions(attrs) do
        case extension_policy() do
          policy when map_size(policy) == 0 ->
            {:ok, attrs}

          policy ->
            top_level_extensions = Map.take(attrs, Map.keys(policy))
            explicit_extensions = normalize_explicit_extensions(Map.get(attrs, "extensions"))
            merged_extensions = Map.merge(top_level_extensions, explicit_extensions)

            with :ok <- validate_required_extensions(policy, merged_extensions),
                 :ok <- validate_forbidden_extensions(policy, merged_extensions),
                 {:ok, validated_extensions} <-
                   validate_policy_extension_data(merged_extensions) do
              attrs =
                attrs
                |> Map.drop(Map.keys(policy))
                |> put_normalized_extensions(validated_extensions)

              {:ok, attrs}
            end
        end
      end

      defp put_normalized_extensions(attrs, extensions) when map_size(extensions) == 0 do
        Map.delete(attrs, "extensions")
      end

      defp put_normalized_extensions(attrs, extensions) do
        Map.put(attrs, "extensions", extensions)
      end

      defp normalize_explicit_extensions(extensions) when is_map(extensions) do
        Map.new(extensions, fn {key, value} -> {to_string(key), value} end)
      end

      defp normalize_explicit_extensions(_), do: %{}

      defp validate_required_extensions(policy, effective_extensions) do
        case Enum.find(policy, fn {namespace, mode} ->
               mode == :required and not Map.has_key?(effective_extensions, namespace)
             end) do
          {namespace, :required} ->
            {:error,
             "Signal #{inspect(__MODULE__)} requires extension namespace #{inspect(namespace)} during typed construction"}

          nil ->
            :ok
        end
      end

      defp validate_forbidden_extensions(policy, effective_extensions) do
        case Enum.find(policy, fn {namespace, mode} ->
               mode == :forbidden and Map.has_key?(effective_extensions, namespace)
             end) do
          {namespace, :forbidden} ->
            {:error,
             "Signal #{inspect(__MODULE__)} forbids extension namespace #{inspect(namespace)} during typed construction"}

          nil ->
            :ok
        end
      end

      defp validate_policy_extension_data(effective_extensions) do
        Enum.reduce_while(effective_extensions, {:ok, %{}}, fn {namespace, data}, {:ok, acc} ->
          case Map.fetch(extension_policy_modules(), namespace) do
            {:ok, extension_module} ->
              case Ext.safe_validate_data(extension_module, data) do
                {:ok, {:ok, validated_data}} ->
                  {:cont, {:ok, Map.put(acc, namespace, validated_data)}}

                {:ok, {:error, reason}} ->
                  {:halt,
                   {:error,
                    "Signal #{inspect(__MODULE__)} received invalid data for extension namespace #{inspect(namespace)}: #{reason}"}}

                {:error, reason} ->
                  {:halt,
                   {:error,
                    "Signal #{inspect(__MODULE__)} failed to validate extension namespace #{inspect(namespace)}: #{inspect(reason)}"}}
              end

            :error ->
              {:cont, {:ok, Map.put(acc, namespace, data)}}
          end
        end)
      end

      defp extension_policy_modules, do: @extension_policy_modules
    end
  end

  @doc false
  defmacro define_caller_module_functions do
    quote location: :keep do
      defp get_caller_module do
        {mod, _fun, _arity, _info} = find_caller_from_stacktrace()
        to_string(mod)
      end

      defp find_caller_from_stacktrace do
        self()
        |> Process.info(:current_stacktrace)
        |> elem(1)
        |> Enum.find(&non_signal_module?/1)
      end

      defp non_signal_module?({mod, _fun, _arity, _info}) do
        mod_str = to_string(mod)
        mod_str != "Elixir.Jido.Signal" and mod_str != "Elixir.Process"
      end
    end
  end
end
