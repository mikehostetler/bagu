defmodule Jido.Signal do
  @moduledoc """
  Defines the core Signal structure in Jido, implementing the CloudEvents specification (v1.0.2)
  with Jido-specific extensions for agent-based systems.

  https://cloudevents.io/

  ## Overview

  Signals are the universal message format in Jido, serving as the nervous system of your
  agent-based application. Every event, command, and state change flows through the system
  as a Signal, providing:

  - Standardized event structure (CloudEvents v1.0.2 compatible)
  - Rich metadata and context tracking
  - Flexible dispatch configuration
  - Automatic serialization

  ## CloudEvents Compliance

  Each Signal implements the CloudEvents v1.0.2 specification with these required fields:

  - `specversion`: Always "1.0.2"
  - `id`: Unique identifier (UUID v4)
  - `source`: Origin of the event ("/service/component")
  - `type`: Classification of the event ("domain.entity.action")

  And optional fields:

  - `subject`: Specific subject of the event
  - `time`: Timestamp in ISO 8601 format
  - `datacontenttype`: Media type of the data (defaults to "application/json")
  - `dataschema`: Schema defining the data structure
  - `data`: The actual event payload

  ## Jido Extensions

  Beyond the CloudEvents spec, Signals support a flexible extension system for
  adding custom metadata and behavior. See `Jido.Signal.Ext` for details.

  ## Creating Signals

  Signals can be created in several ways (prefer the positional new/3):

  ```elixir
  alias Jido.Signal

  # Preferred: positional constructor (type, data, attrs)
  {:ok, signal} = Signal.new("metrics.collected", %{cpu: 80, memory: 70},
    source: "/monitoring"
  )

  # Also available: map/keyword constructor (backwards compatible)
  {:ok, signal} = Signal.new(%{
    type: "user.created",
    source: "/auth/registration",
    data: %{user_id: "123", email: "user@example.com"}
  })

  # Data payloads follow CloudEvents rules:
  # - When datacontenttype is JSON (or omitted in JSON format), `data` can be any JSON value
  #   (object/map, array, string, number, boolean, null)
  # - For non-JSON payloads, encode according to datacontenttype; binary payloads use data_base64 during JSON serialization
  ```

  ## Custom Signal Types

  You can define custom Signal types using the `use Jido.Signal` pattern:

  ```elixir
  defmodule MySignal do
    use Jido.Signal,
      type: "my.custom.signal",
      default_source: "/my/service",
      datacontenttype: "application/json",
      schema: [
        user_id: [type: :string, required: true],
        message: [type: :string, required: true]
      ]
  end

  # Create instances
  {:ok, signal} = MySignal.new(%{user_id: "123", message: "Hello"})

  # Override runtime fields
  {:ok, signal} = MySignal.new(
    %{user_id: "123", message: "Hello"},
    source: "/different/source",
    subject: "user-notification"
  )
  ```

  ## Signal Types

  Signal types are strings, but typically use a hierarchical dot notation:

  ```
  <domain>.<entity>.<action>[.<qualifier>]
  ```

  Examples:
  - `user.profile.updated`
  - `order.payment.processed.success`
  - `system.metrics.collected`

  Guidelines for type naming:
  - Use lowercase with dots
  - Keep segments meaningful
  - Order from general to specific
  - Include qualifiers when needed

  ## Data Content Types

  The `datacontenttype` field indicates the format of the `data` field:

  - `application/json` (default) - JSON-structured data
  - `text/plain` - Unstructured text
  - `application/octet-stream` - Binary data
  - Custom MIME types for specific formats

  ## Dispatch Configuration

  Signal dispatch is configured when subscribing to the Bus or when calling Dispatch directly:

  ```elixir
  # Configure dispatch when subscribing
  Bus.subscribe(bus, "user.*", dispatch: {:pubsub, topic: "events"})

  # Or dispatch directly with config
  Dispatch.dispatch(signal, {:logger, level: :info})
  ```

  ## See Also

  - `Jido.Signal.Router` - Signal routing
  - `Jido.Signal.Dispatch` - Dispatch handling
  - CloudEvents spec: https://cloudevents.io/
  """

  import Jido.Signal.Ext.Registry, only: [get: 1]

  alias Jido.Signal.Error
  alias Jido.Signal.Ext
  alias Jido.Signal.ID
  alias Jido.Signal.Serialization.Serializer
  alias Jido.Signal.Serialization.TypeProvider
  alias Jido.Signal.Using

  require Logger

  @core_attrs ~w[
    specversion id source type subject time
    datacontenttype dataschema data jido_dispatch extensions
  ]a

  @signal_config_schema NimbleOptions.new!(
                          type: [
                            type: :string,
                            required: true,
                            doc: "The type of the Signal"
                          ],
                          default_source: [
                            type: :string,
                            required: false,
                            doc: "The default source of the Signal"
                          ],
                          datacontenttype: [
                            type: :string,
                            required: false,
                            doc: "The content type of the data field"
                          ],
                          dataschema: [
                            type: :string,
                            required: false,
                            doc: "Schema URI for the data field (optional)"
                          ],
                          schema: [
                            type: :keyword_list,
                            default: [],
                            doc:
                              "A NimbleOptions schema for validating the Signal's data parameters"
                          ],
                          extension_policy: [
                            type: :keyword_list,
                            default: [],
                            doc:
                              "Typed-signal extension policy as `{ExtensionModule, :required | :optional | :forbidden}` entries"
                          ]
                        )

  @extension_policy_modes [:required, :optional, :forbidden]

  # Zoi schema for Signal struct - testing new default pattern
  @signal_schema Zoi.struct(
                   __MODULE__,
                   %{
                     # Required fields
                     id: Zoi.string(),
                     source: Zoi.string(),
                     type: Zoi.string(),
                     # Test: Zoi.default(...) |> Zoi.optional() pattern for static defaults
                     specversion: Zoi.default(Zoi.string(), "1.0.2") |> Zoi.optional(),
                     datacontenttype:
                       Zoi.default(Zoi.string(), "application/json") |> Zoi.optional(),
                     extensions: Zoi.default(Zoi.map(), %{}) |> Zoi.optional(),
                     # Optional fields
                     subject: Zoi.string() |> Zoi.nullable() |> Zoi.optional(),
                     time: Zoi.string() |> Zoi.nullable() |> Zoi.optional(),
                     dataschema: Zoi.string() |> Zoi.nullable() |> Zoi.optional(),
                     data: Zoi.any() |> Zoi.optional(),
                     jido_dispatch: Zoi.any() |> Zoi.optional()
                   }
                 )

  @derive {Jason.Encoder,
           only: [
             :id,
             :source,
             :type,
             :subject,
             :time,
             :datacontenttype,
             :dataschema,
             :data,
             :specversion,
             :extensions
           ]}

  # Use Zoi.Struct helpers for automatic generation
  @type t :: unquote(Zoi.type_spec(@signal_schema))
  @enforce_keys Zoi.Struct.enforce_keys(@signal_schema)
  defstruct Zoi.Struct.struct_fields(@signal_schema)

  @doc "Returns the Zoi schema for Signal"
  def schema, do: @signal_schema

  @doc """
  Defines a new Signal module.

  This macro sets up the necessary structure and callbacks for a custom Signal,
  including configuration validation and default implementations.

  ## Options

  #{NimbleOptions.docs(@signal_config_schema)}

  ## Examples

      defmodule MySignal do
        use Jido.Signal,
          type: "my.custom.signal",
          default_source: "/my/service",
          schema: [
            user_id: [type: :string, required: true],
            message: [type: :string, required: true]
          ],
          extension_policy: [
            {MyApp.Signal.Ext.Trace, :required},
            {MyApp.Signal.Ext.Dispatch, :forbidden}
          ]
      end

  """
  defmacro __using__(opts) do
    escaped_schema = Macro.escape(@signal_config_schema)

    quote location: :keep do
      alias Jido.Signal
      alias Jido.Signal.Error
      alias Jido.Signal.ID
      alias Jido.Signal.Using

      require Using

      case NimbleOptions.validate(unquote(opts), unquote(escaped_schema)) do
        {:ok, validated_opts} ->
          case Signal.normalize_extension_policy(validated_opts[:extension_policy]) do
            {:ok, extension_policy} ->
              Module.put_attribute(
                __MODULE__,
                :extension_policy_modules,
                Signal.build_extension_policy_modules(validated_opts[:extension_policy])
              )

              Module.put_attribute(
                __MODULE__,
                :validated_opts,
                Keyword.put(validated_opts, :extension_policy, extension_policy)
              )

              Using.define_signal_functions()

            {:error, error} ->
              message = Error.format_nimble_config_error(error, "Signal", __MODULE__)
              raise CompileError, description: message, file: __ENV__.file, line: __ENV__.line
          end

        {:error, error} ->
          message = Error.format_nimble_config_error(error, "Signal", __MODULE__)
          raise CompileError, description: message, file: __ENV__.file, line: __ENV__.line
      end
    end
  end

  @doc false
  @spec normalize_extension_policy(keyword()) ::
          {:ok, %{optional(String.t()) => :required | :optional | :forbidden}}
          | {:error, String.t()}
  def normalize_extension_policy(policy) when is_list(policy) do
    Enum.reduce_while(policy, {:ok, %{}}, fn {extension_module, mode}, {:ok, acc} ->
      with :ok <- validate_extension_policy_module(extension_module),
           :ok <- validate_extension_policy_mode(extension_module, mode),
           {:ok, namespace} <- fetch_extension_policy_namespace(extension_module),
           :ok <- ensure_unique_extension_policy_namespace(namespace, acc) do
        {:cont, {:ok, Map.put(acc, namespace, mode)}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @doc false
  @spec build_extension_policy_modules(keyword()) :: %{optional(String.t()) => module()}
  def build_extension_policy_modules(policy) when is_list(policy) do
    Enum.reduce(policy, %{}, fn {extension_module, _mode}, acc ->
      Map.put(acc, extension_module.namespace(), extension_module)
    end)
  end

  defp validate_extension_policy_module(extension_module) when is_atom(extension_module) do
    case Code.ensure_compiled(extension_module) do
      {:module, _module} ->
        if function_exported?(extension_module, :namespace, 0) do
          :ok
        else
          {:error,
           "extension_policy keys must be compiled modules implementing namespace/0, got: #{inspect(extension_module)}"}
        end

      {:error, _reason} ->
        {:error,
         "extension_policy keys must be compiled modules implementing namespace/0, got: #{inspect(extension_module)}"}
    end
  end

  defp validate_extension_policy_module(extension_module) do
    {:error,
     "extension_policy keys must be compiled modules implementing namespace/0, got: #{inspect(extension_module)}"}
  end

  defp validate_extension_policy_mode(_extension_module, mode)
       when mode in @extension_policy_modes,
       do: :ok

  defp validate_extension_policy_mode(extension_module, mode) do
    {:error,
     "extension_policy for #{inspect(extension_module)} must be one of #{inspect(@extension_policy_modes)}, got: #{inspect(mode)}"}
  end

  defp fetch_extension_policy_namespace(extension_module) do
    namespace = extension_module.namespace()

    if is_binary(namespace) and byte_size(namespace) > 0 do
      {:ok, namespace}
    else
      {:error,
       "extension_policy module #{inspect(extension_module)} returned an invalid namespace: #{inspect(namespace)}"}
    end
  end

  defp ensure_unique_extension_policy_namespace(namespace, acc) do
    if Map.has_key?(acc, namespace) do
      {:error, "extension_policy declares namespace #{inspect(namespace)} more than once"}
    else
      :ok
    end
  end

  @doc """
  Creates a new Signal struct with explicit type and data, raising an error if invalid.

  ## Parameters

  - `type`: A string representing the event type (e.g., `"user.created"`).
  - `data`: The payload (any term; see CloudEvents rules below).
  - `attrs`: (Optional) A map or keyword list of additional Signal attributes (e.g., `:source`, `:subject`).

  ## Returns

  `Signal.t()` if the attributes are valid.

  ## Raises

  `ArgumentError` if the attributes are invalid.

  ## Examples

      signal = Jido.Signal.new!("user.created", %{user_id: "123"}, source: "/auth")
      {signal.type, signal.source, signal.data}
      # => {"user.created", "/auth", %{user_id: "123"}}

      signal = Jido.Signal.new!("user.created", %{user_id: "123"})
      signal.type
      # => "user.created"

  """
  @spec new!(String.t(), term(), map() | keyword()) :: t() | no_return()
  def new!(type, data, attrs \\ %{}) do
    case new(type, data, attrs) do
      {:ok, signal} -> signal
      {:error, reason} -> raise ArgumentError, "invalid signal: #{reason}"
    end
  end

  @doc """
  Creates a new Signal struct, raising an error if invalid.

  ## Parameters

  - `attrs`: A map or keyword list containing the Signal attributes.

  ## Returns

  `Signal.t()` if the attributes are valid.

  ## Raises

  `RuntimeError` if the attributes are invalid.

  ## Examples

      signal = Jido.Signal.new!(%{type: "example.event", source: "/example"})
      {signal.type, signal.source}
      # => {"example.event", "/example"}

      signal = Jido.Signal.new!(type: "example.event", source: "/example")
      {signal.type, signal.source}
      # => {"example.event", "/example"}

  """
  @spec new!(map() | keyword()) :: t() | no_return()
  def new!(attrs) do
    case new(attrs) do
      {:ok, signal} -> signal
      {:error, reason} -> raise reason
    end
  end

  @doc """
  Creates a new Signal struct.

  ## Parameters

  - `attrs`: A map or keyword list containing the Signal attributes.

  ## Returns

  `{:ok, Signal.t()}` if the attributes are valid, `{:error, String.t()}` otherwise.

  ## Examples

      {:ok, signal} = Jido.Signal.new(%{type: "example.event", source: "/example", id: "123"})
      {signal.type, signal.source, signal.id}
      # => {"example.event", "/example", "123"}

      {:ok, signal} = Jido.Signal.new(type: "example.event", source: "/example")
      {signal.type, signal.source}
      # => {"example.event", "/example"}

  """
  @reserved_keys [:type, "type", :data, "data"]

  @spec new(map() | keyword()) :: {:ok, t()} | {:error, String.t()}
  def new(attrs) when is_list(attrs) do
    attrs |> Map.new() |> new()
  end

  def new(attrs) when is_map(attrs) do
    caller =
      self()
      |> Process.info(:current_stacktrace)
      |> elem(1)
      |> Enum.find(fn {mod, _fun, _arity, _info} ->
        mod_str = to_string(mod)
        mod_str != "Elixir.Jido.Signal" and mod_str != "Elixir.Process"
      end)
      |> elem(0)
      |> to_string()

    defaults = %{
      "id" => ID.generate!(),
      "source" => caller,
      "specversion" => "1.0.2",
      "time" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    attrs
    |> Map.new(fn {k, v} -> {to_string(k), v} end)
    |> Map.merge(defaults, fn _k, user_val, _default_val -> user_val end)
    |> from_map()
  end

  @doc """
  Creates a Signal with explicit type and payload, plus optional attrs.

  - `type` must be a string
  - `data` can be any term (map, string, etc.)
  - `attrs` is a map or keyword list for other fields (e.g., `:source`, `:subject`, `:jido_dispatch`)
  - `attrs` must NOT include `:type`/`"type"` or `:data`/`"data"`

  Examples:
      iex> {:ok, s} = Jido.Signal.new("user.created", %{user_id: "123"}, source: "/auth")
      iex> s.type
      "user.created"
      iex> {:ok, s} = Jido.Signal.new("log.message", "Hello world")
      iex> s.data
      "Hello world"
  """
  @spec new(String.t(), term(), map() | keyword()) :: {:ok, t()} | {:error, String.t()}
  def new(type, data, attrs \\ %{})

  def new(type, data, attrs) when is_binary(type) and (is_map(attrs) or is_list(attrs)) do
    with {:ok, normalized_attrs} <- normalize_and_validate_attrs(attrs) do
      normalized_attrs
      |> Map.merge(%{data: data, type: type})
      |> new()
    end
  end

  def new(_, _, _),
    do: {:error, "expected new/3 (type :: String.t(), data :: any(), attrs :: map/keyword)"}

  defp normalize_and_validate_attrs(attrs) when is_list(attrs) do
    normalize_and_validate_attrs(Map.new(attrs))
  end

  defp normalize_and_validate_attrs(attrs) when is_map(attrs) do
    case Enum.find(@reserved_keys, &Map.has_key?(attrs, &1)) do
      nil -> {:ok, attrs}
      key -> {:error, "attribute #{inspect(key)} must not be passed in attrs when calling new/3"}
    end
  end

  @doc """
  Creates a new Signal struct from a map.

  ## Parameters

  - `map`: A map containing the Signal attributes.

  ## Returns

  `{:ok, Signal.t()}` if the map is valid, `{:error, String.t()}` otherwise.

  ## Examples

      {:ok, signal} =
        Jido.Signal.from_map(%{"type" => "example.event", "source" => "/example", "id" => "123"})

      {signal.type, signal.source, signal.id}
      # => {"example.event", "/example", "123"}

  """
  @spec from_map(map()) :: {:ok, t()} | {:error, String.t()}
  def from_map(map) when is_map(map) do
    {extensions_data, remaining_attrs} = inflate_extensions(map)

    # Parse extensions that were explicitly stored in "extensions" field
    final_extensions =
      case parse_extensions(remaining_attrs["extensions"]) do
        {:ok, explicit} -> Map.merge(extensions_data, explicit)
        {:error, _} -> extensions_data
      end

    {core, maybe_ext} = Map.split(remaining_attrs, @core_attrs |> Enum.map(&to_string/1))

    unknown_extensions =
      Enum.reduce(maybe_ext, %{}, fn {k, v}, acc ->
        ns = to_string(k)

        case Jido.Signal.Ext.Registry.get(ns) do
          {:ok, _mod} ->
            acc

          {:error, :not_found} ->
            Logger.warning("Unknown extension '#{ns}' encountered - preserving as opaque data")
            Map.put(acc, ns, v)
        end
      end)

    all_extensions = Map.merge(final_extensions, unknown_extensions)
    remaining_attrs = core

    with :ok <- parse_specversion(remaining_attrs),
         {:ok, type} <- parse_type(remaining_attrs),
         {:ok, source} <- parse_source(remaining_attrs),
         {:ok, id} <- parse_id(remaining_attrs),
         {:ok, subject} <- parse_subject(remaining_attrs),
         {:ok, time} <- parse_time(remaining_attrs),
         {:ok, datacontenttype} <- parse_datacontenttype(remaining_attrs),
         {:ok, dataschema} <- parse_dataschema(remaining_attrs),
         {:ok, data} <- parse_data(remaining_attrs["data"]),
         {:ok, jido_dispatch} <- parse_jido_dispatch(remaining_attrs["jido_dispatch"]) do
      event = %__MODULE__{
        data: data,
        datacontenttype: datacontenttype || if(data, do: "application/json"),
        dataschema: dataschema,
        extensions: all_extensions,
        id: id,
        jido_dispatch: jido_dispatch,
        source: source,
        specversion: "1.0.2",
        subject: subject,
        time: time,
        type: type
      }

      {:ok, event}
    else
      {:error, reason} -> {:error, "parse error: #{reason}"}
    end
  end

  @doc """
  Converts a struct or list of structs to Signal data format.

  This function is useful for converting domain objects to Signal format
  while preserving their type information through the TypeProvider.

  ## Parameters

  - `signals`: A struct or list of structs to convert
  - `fields`: Additional fields to include (currently unused)

  ## Returns

  Signal struct or list of Signal structs with the original data as payload

  ## Examples

      # Converting a single struct
      iex> user = %User{id: 1, name: "John"}
      iex> signal = Jido.Signal.map_to_signal_data(user)
      iex> signal.data
      %User{id: 1, name: "John"}

      # Converting multiple structs
      iex> users = [%User{id: 1}, %User{id: 2}]
      iex> signals = Jido.Signal.map_to_signal_data(users)
      iex> length(signals)
      2
  """
  def map_to_signal_data(signals, fields \\ [])

  @spec map_to_signal_data(list(struct), Keyword.t()) :: list(t())
  def map_to_signal_data(signals, fields) when is_list(signals) do
    Enum.map(signals, &map_to_signal_data(&1, fields))
  end

  @spec map_to_signal_data(struct, Keyword.t()) :: t()
  def map_to_signal_data(signal, fields) do
    source = Keyword.get(fields, :source, "/#{inspect(signal.__struct__)}")

    %__MODULE__{
      data: signal,
      id: ID.generate!(),
      source: source,
      type: TypeProvider.to_string(signal)
    }
  end

  # Parser functions for standard CloudEvents fields

  @spec parse_specversion(map()) :: :ok | {:error, String.t()}
  defp parse_specversion(%{"specversion" => "1.0.2"}), do: :ok
  defp parse_specversion(%{"specversion" => x}), do: {:error, "unexpected specversion #{x}"}
  defp parse_specversion(_), do: {:error, "missing specversion"}

  @spec parse_type(map()) :: {:ok, String.t()} | {:error, String.t()}
  defp parse_type(%{"type" => type}) when byte_size(type) > 0, do: {:ok, type}
  defp parse_type(_), do: {:error, "missing type"}

  @spec parse_source(map()) :: {:ok, String.t()} | {:error, String.t()}
  defp parse_source(%{"source" => source}) when byte_size(source) > 0, do: {:ok, source}
  defp parse_source(_), do: {:error, "missing source"}

  @spec parse_id(map()) :: {:ok, String.t()} | {:error, String.t()}
  defp parse_id(%{"id" => id}) when byte_size(id) > 0, do: {:ok, id}
  defp parse_id(%{"id" => ""}), do: {:error, "id given but empty"}
  defp parse_id(_), do: {:ok, ID.generate!()}

  @spec parse_subject(map()) :: {:ok, String.t() | nil} | {:error, String.t()}
  defp parse_subject(%{"subject" => sub}) when byte_size(sub) > 0, do: {:ok, sub}
  defp parse_subject(%{"subject" => ""}), do: {:error, "subject given but empty"}
  defp parse_subject(_), do: {:ok, nil}

  @spec parse_time(map()) :: {:ok, String.t() | nil} | {:error, String.t()}
  defp parse_time(%{"time" => time}) when byte_size(time) > 0, do: {:ok, time}
  defp parse_time(%{"time" => ""}), do: {:error, "time given but empty"}
  defp parse_time(_), do: {:ok, nil}

  @spec parse_datacontenttype(map()) :: {:ok, String.t() | nil} | {:error, String.t()}
  defp parse_datacontenttype(%{"datacontenttype" => ct}) when byte_size(ct) > 0, do: {:ok, ct}

  defp parse_datacontenttype(%{"datacontenttype" => ""}),
    do: {:error, "datacontenttype given but empty"}

  defp parse_datacontenttype(_), do: {:ok, nil}

  @spec parse_dataschema(map()) :: {:ok, String.t() | nil} | {:error, String.t()}
  defp parse_dataschema(%{"dataschema" => schema}) when byte_size(schema) > 0, do: {:ok, schema}
  defp parse_dataschema(%{"dataschema" => ""}), do: {:error, "dataschema given but empty"}
  defp parse_dataschema(_), do: {:ok, nil}

  @spec parse_data(term()) :: {:ok, term()} | {:error, String.t()}
  defp parse_data(""), do: {:error, "data field given but empty"}
  defp parse_data(data), do: {:ok, data}

  @spec parse_jido_dispatch(term()) :: {:ok, term() | nil} | {:error, String.t()}
  defp parse_jido_dispatch(nil), do: {:ok, nil}

  defp parse_jido_dispatch({adapter, opts} = config) when is_atom(adapter) and is_list(opts) do
    IO.warn(
      "Signal.jido_dispatch field is deprecated and will be removed in the next major version. " <>
        "Use the Dispatch extension or pass dispatch configs to Bus.subscribe/3 or Dispatch.dispatch/2 instead.",
      []
    )

    {:ok, config}
  end

  defp parse_jido_dispatch(config) when is_list(config) do
    IO.warn(
      "Signal.jido_dispatch field is deprecated and will be removed in the next major version. " <>
        "Use the Dispatch extension or pass dispatch configs to Bus.subscribe/3 or Dispatch.dispatch/2 instead.",
      []
    )

    {:ok, config}
  end

  defp parse_jido_dispatch(_), do: {:error, "invalid dispatch config"}

  @spec parse_extensions(term()) :: {:ok, map()} | {:error, String.t()}
  defp parse_extensions(nil), do: {:ok, %{}}
  defp parse_extensions(extensions) when is_map(extensions), do: {:ok, extensions}
  defp parse_extensions(_), do: {:error, "invalid extensions"}

  @doc """
  Serializes a Signal or a list of Signals using the specified or default serializer.

  ## Parameters

  - `signal_or_list`: A Signal struct or list of Signal structs
  - `opts`: Optional configuration including:
    - `:serializer` - The serializer module to use (defaults to configured serializer)

  ## Returns

  `{:ok, binary}` on success, `{:error, reason}` on failure

  ## Examples

      iex> signal = %Jido.Signal{type: "example.event", source: "/example"}
      iex> {:ok, binary} = Jido.Signal.serialize(signal)
      iex> is_binary(binary)
      true

      # Using a specific serializer
      iex> {:ok, binary} = Jido.Signal.serialize(signal, serializer: Jido.Signal.Serialization.ErlangTermSerializer)
      iex> is_binary(binary)
      true

      # Serializing multiple Signals
      iex> signals = [
      ...>   %Jido.Signal{type: "event1", source: "/ex1"},
      ...>   %Jido.Signal{type: "event2", source: "/ex2"}
      ...> ]
      iex> {:ok, binary} = Jido.Signal.serialize(signals)
      iex> is_binary(binary)
      true
  """
  @spec serialize(t() | list(t()), keyword()) :: {:ok, binary()} | {:error, term()}
  def serialize(signal_or_list, opts \\ [])

  def serialize(%__MODULE__{} = signal, opts) do
    Serializer.serialize(signal, opts)
  end

  def serialize(signals, opts) when is_list(signals) do
    Serializer.serialize(signals, opts)
  end

  @doc """
  Legacy serialize function that returns binary directly (for backward compatibility).
  """
  @spec serialize!(t() | list(t()), keyword()) :: binary()
  def serialize!(signal_or_list, opts \\ []) do
    case serialize(signal_or_list, opts) do
      {:ok, binary} -> binary
      {:error, reason} -> raise "Serialization failed: #{reason}"
    end
  end

  @doc """
  Deserializes binary data back into a Signal struct or list of Signal structs.

  ## Parameters

  - `binary`: The serialized binary data to deserialize
  - `opts`: Optional configuration including:
    - `:serializer` - The serializer module to use (defaults to configured serializer)
    - `:type` - Specific type to deserialize to
    - `:type_provider` - Custom type provider

  ## Returns

  `{:ok, Signal.t() | list(Signal.t())}` if successful, `{:error, reason}` otherwise

  ## Examples

      # JSON deserialization (default)
      iex> json = ~s({"type":"example.event","source":"/example","id":"123"})
      iex> {:ok, signal} = Jido.Signal.deserialize(json)
      iex> signal.type
      "example.event"

      # Using a specific serializer
      iex> {:ok, signal} = Jido.Signal.deserialize(binary, serializer: Jido.Signal.Serialization.ErlangTermSerializer)
      iex> signal.type
      "example.event"

      # Deserializing multiple Signals
      iex> json = ~s([{"type":"event1","source":"/ex1"},{"type":"event2","source":"/ex2"}])
      iex> {:ok, signals} = Jido.Signal.deserialize(json)
      iex> length(signals)
      2
  """
  @spec deserialize(binary(), keyword()) :: {:ok, t() | list(t())} | {:error, term()}
  def deserialize(binary, opts \\ []) when is_binary(binary) do
    with {:ok, data} <- Serializer.deserialize(binary, opts) do
      deserialize_data(data)
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp deserialize_data(data) when is_list(data) do
    {:ok, Enum.map(data, &convert_to_signal!/1)}
  end

  defp deserialize_data(data) do
    {:ok, convert_to_signal!(data)}
  end

  defp convert_to_signal!(signal_data) do
    case convert_to_signal(signal_data) do
      {:ok, signal} -> signal
      {:error, reason} -> raise "Failed to parse signal: #{reason}"
    end
  end

  # Convert deserialized data to Signal struct
  defp convert_to_signal(%__MODULE__{} = signal), do: {:ok, signal}

  defp convert_to_signal(data) when is_map(data) do
    from_map(data)
  end

  defp convert_to_signal(data) do
    {:error, "Cannot convert #{inspect(data)} to Signal"}
  end

  @doc """
  Adds extension data to a Signal.

  Validates the extension data against the extension's schema and stores it
  in the Signal's extensions map under the extension's namespace.

  ## Parameters

  - `signal` - The Signal struct to add the extension to
  - `namespace` - The extension namespace (string)
  - `data` - The extension data to add

  ## Returns

  `{:ok, Signal.t()}` if successful, `{:error, reason}` if validation fails

  ## Examples

      # Add authentication extension data
      {:ok, signal} = Jido.Signal.put_extension(signal, "auth", %{user_id: "123"})

      # Validation will occur based on extension schema
      {:ok, signal} = Jido.Signal.put_extension(signal, "tracking", %{session_id: "abc"})
  """
  @spec put_extension(t(), String.t(), term()) :: {:ok, t()} | {:error, String.t()}
  def put_extension(%__MODULE__{} = signal, namespace, data) when is_binary(namespace) do
    case get(namespace) do
      {:ok, extension_module} ->
        case Ext.safe_validate_data(extension_module, data) do
          {:ok, {:ok, validated_data}} ->
            updated_extensions = Map.put(signal.extensions, namespace, validated_data)
            {:ok, %{signal | extensions: updated_extensions}}

          {:ok, {:error, reason}} ->
            {:error, reason}

          {:error, reason} ->
            {:error, "extension #{namespace} validation failed: #{inspect(reason)}"}
        end

      {:error, :not_found} ->
        {:error, "Unknown extension: #{namespace}"}
    end
  end

  def put_extension(_, _, _) do
    {:error, "Expected Signal struct, namespace string, and extension data"}
  end

  @doc """
  Retrieves extension data from a Signal.

  Returns the extension data stored under the given namespace, or nil
  if no data exists for that extension.

  ## Parameters

  - `signal` - The Signal struct to retrieve from
  - `namespace` - The extension namespace (string)

  ## Returns

  The extension data if present, `nil` otherwise

  ## Examples

      # Retrieve authentication data
      auth_data = Jido.Signal.get_extension(signal, "auth")
      # => %{user_id: "123", roles: ["user"]}

      # Non-existent extension returns nil
      missing = Jido.Signal.get_extension(signal, "nonexistent")
      # => nil
  """
  @spec get_extension(t(), String.t()) :: term() | nil
  def get_extension(%__MODULE__{} = signal, namespace) when is_binary(namespace) do
    case get(namespace) do
      {:ok, _extension_module} ->
        Map.get(signal.extensions, namespace)

      {:error, :not_found} ->
        nil
    end
  end

  def get_extension(_, _), do: nil

  @doc """
  Removes extension data from a Signal.

  Removes the extension data stored under the given namespace and returns
  the updated Signal.

  ## Parameters

  - `signal` - The Signal struct to remove from
  - `namespace` - The extension namespace (string)

  ## Returns

  The updated Signal struct with the extension removed

  ## Examples

      # Remove authentication extension
      updated_signal = Jido.Signal.delete_extension(signal, "auth")

      # Extension data is no longer present
      nil = Jido.Signal.get_extension(updated_signal, "auth")
  """
  @spec delete_extension(t(), String.t()) :: t()
  def delete_extension(%__MODULE__{} = signal, namespace) when is_binary(namespace) do
    updated_extensions = Map.delete(signal.extensions, namespace)
    %{signal | extensions: updated_extensions}
  end

  def delete_extension(signal, _), do: signal

  @doc """
  Lists all extensions currently present on a Signal.

  Returns a list of extension namespace strings for extensions that have
  data stored in the Signal.

  ## Parameters

  - `signal` - The Signal struct to inspect

  ## Returns

  A list of extension namespace strings

  ## Examples

      # Signal with multiple extensions
      extensions = Jido.Signal.list_extensions(signal)
      # => ["auth", "tracking", "metadata"]

      # Signal with no extensions
      extensions = Jido.Signal.list_extensions(signal)
      # => []
  """
  @spec list_extensions(t()) :: [String.t()]
  def list_extensions(%__MODULE__{} = signal) do
    Map.keys(signal.extensions)
  end

  def list_extensions(_), do: []

  @doc """
  Flattens extension data to CloudEvents-compliant top-level attributes.

  Takes a Signal struct and converts all extension data to top-level attributes
  by calling each extension's `to_attrs/1` function and merging the results
  into the base signal map.

  ## Parameters

  - `signal` - The Signal struct containing extensions to flatten

  ## Returns

  A map with extensions flattened to top-level CloudEvents attributes

  ## Examples

      signal = %Signal{type: "test", source: "/test", extensions: %{"auth" => %{user_id: "123"}}}
      flattened = Jido.Signal.flatten_extensions(signal)
      # => %{"type" => "test", "source" => "/test", "user_id" => "123", ...}
  """
  @spec flatten_extensions(t()) :: map()
  def flatten_extensions(%__MODULE__{} = signal) do
    base_map = build_base_map_for_flatten(signal)
    Enum.reduce(signal.extensions, base_map, &flatten_single_extension/2)
  end

  defp build_base_map_for_flatten(signal) do
    required_fields = ["specversion", "type", "source", "id"]

    signal
    |> Map.from_struct()
    |> Map.delete(:extensions)
    |> Enum.reject(fn {k, v} ->
      string_key = to_string(k)
      v == nil and string_key not in required_fields
    end)
    |> Map.new(fn {k, v} -> {to_string(k), v} end)
  end

  defp flatten_single_extension({namespace, data}, acc) do
    case get(namespace) do
      {:ok, extension_module} -> flatten_extension_attrs(extension_module, namespace, data, acc)
      {:error, :not_found} -> acc
    end
  end

  defp flatten_extension_attrs(extension_module, namespace, data, acc) do
    case Ext.safe_to_attrs(extension_module, data) do
      {:ok, extension_attrs} ->
        filtered_attrs = Enum.reject(extension_attrs, fn {_k, v} -> v == nil end)
        Map.merge(acc, Map.new(filtered_attrs))

      {:error, reason} ->
        Logger.warning("Extension #{namespace} to_attrs failed: #{inspect(reason)} - skipping")
        acc
    end
  end

  @doc """
  Inflates top-level attributes back to extension data.

  Takes a map of attributes (typically from deserialization) and extracts
  extension data by calling each registered extension's `from_attrs/1` function.
  Returns both the extensions map and the remaining attributes with extension
  data removed.

  ## Parameters

  - `attrs` - Map of attributes to extract extensions from

  ## Returns

  A tuple `{extensions_map, remaining_attrs}` where:
  - `extensions_map` contains extension data keyed by namespace
  - `remaining_attrs` has extension-specific attributes removed

  ## Examples

      attrs = %{"type" => "test", "source" => "/test", "user_id" => "123", "roles" => ["admin"]}
      {extensions, remaining} = Jido.Signal.inflate_extensions(attrs)
      # => {%{"auth" => %{user_id: "123", roles: ["admin"]}}, %{"type" => "test", "source" => "/test"}}
  """
  @core_cloudevents_fields [
    "specversion",
    "type",
    "source",
    "id",
    "subject",
    "time",
    "datacontenttype",
    "dataschema",
    "data",
    "jido_dispatch"
  ]

  @spec inflate_extensions(map()) :: {map(), map()}
  def inflate_extensions(attrs) when is_map(attrs) do
    all_extensions = Jido.Signal.Ext.Registry.all()
    Enum.reduce(all_extensions, {%{}, attrs}, &inflate_single_extension/2)
  end

  defp inflate_single_extension({namespace, extension_module}, {ext_acc, attrs_acc}) do
    case Ext.safe_from_attrs(extension_module, attrs_acc) do
      {:ok, nil} ->
        {ext_acc, attrs_acc}

      {:ok, extension_data} ->
        process_extension_data(namespace, extension_module, extension_data, ext_acc, attrs_acc)

      {:error, reason} ->
        Logger.warning("Extension #{namespace} from_attrs failed: #{inspect(reason)} - skipping")
        {ext_acc, attrs_acc}
    end
  end

  defp process_extension_data(namespace, extension_module, extension_data, ext_acc, attrs_acc) do
    if extension_data == attrs_acc and map_size(extension_data) == map_size(attrs_acc) do
      # Extension returned the full attrs map (default behavior)
      process_default_from_attrs(namespace, extension_module, ext_acc, attrs_acc)
    else
      # Extension returned specific data (custom from_attrs)
      process_custom_from_attrs(namespace, extension_module, extension_data, ext_acc, attrs_acc)
    end
  end

  defp process_default_from_attrs(namespace, extension_module, ext_acc, attrs_acc) do
    case has_extension_attributes?(extension_module, attrs_acc) do
      {false, _} ->
        {ext_acc, attrs_acc}

      {true, matching_attrs} ->
        validate_and_store_matching_attrs(
          namespace,
          extension_module,
          matching_attrs,
          ext_acc,
          attrs_acc
        )
    end
  end

  defp validate_and_store_matching_attrs(
         namespace,
         extension_module,
         matching_attrs,
         ext_acc,
         attrs_acc
       ) do
    atom_keyed_attrs = convert_to_atom_keys(matching_attrs)

    if map_size(atom_keyed_attrs) == 0 do
      {ext_acc, attrs_acc}
    else
      validate_and_store_extension(
        namespace,
        extension_module,
        atom_keyed_attrs,
        matching_attrs,
        ext_acc,
        attrs_acc
      )
    end
  end

  defp validate_and_store_extension(
         namespace,
         extension_module,
         atom_keyed_attrs,
         matching_attrs,
         ext_acc,
         attrs_acc
       ) do
    case Ext.safe_validate_data(extension_module, atom_keyed_attrs) do
      {:ok, {:ok, validated_data}} ->
        updated_attrs = remove_non_core_attrs(matching_attrs, attrs_acc)
        {Map.put(ext_acc, namespace, validated_data), updated_attrs}

      {:ok, {:error, _reason}} ->
        {ext_acc, attrs_acc}

      {:error, reason} ->
        Logger.warning(
          "Extension #{namespace} validate_data failed: #{inspect(reason)} - skipping"
        )

        {ext_acc, attrs_acc}
    end
  end

  defp process_custom_from_attrs(namespace, extension_module, extension_data, ext_acc, attrs_acc) do
    case Ext.safe_validate_data(extension_module, extension_data) do
      {:ok, {:ok, validated_data}} ->
        remove_extension_attrs_and_store(
          namespace,
          extension_module,
          validated_data,
          ext_acc,
          attrs_acc
        )

      {:ok, {:error, _reason}} ->
        {ext_acc, attrs_acc}

      {:error, reason} ->
        Logger.warning(
          "Extension #{namespace} validate_data failed: #{inspect(reason)} - skipping"
        )

        {ext_acc, attrs_acc}
    end
  end

  defp remove_extension_attrs_and_store(
         namespace,
         extension_module,
         validated_data,
         ext_acc,
         attrs_acc
       ) do
    case Ext.safe_to_attrs(extension_module, validated_data) do
      {:ok, extension_attrs} ->
        updated_attrs = remove_non_core_attrs(extension_attrs, attrs_acc)
        {Map.put(ext_acc, namespace, validated_data), updated_attrs}

      {:error, reason} ->
        Logger.warning("Extension #{namespace} to_attrs failed: #{inspect(reason)} - skipping")
        {ext_acc, attrs_acc}
    end
  end

  defp convert_to_atom_keys(attrs) do
    Enum.reduce(attrs, %{}, fn {k, v}, acc ->
      try do
        Map.put(acc, String.to_existing_atom(k), v)
      rescue
        ArgumentError -> acc
      end
    end)
  end

  defp remove_non_core_attrs(attrs_to_remove, attrs_acc) do
    Enum.reduce(attrs_to_remove, attrs_acc, fn {key, _value}, acc ->
      if key in @core_cloudevents_fields, do: acc, else: Map.delete(acc, key)
    end)
  end

  defp has_extension_attributes?(extension_module, attrs) do
    case extension_module.schema() do
      [] ->
        {false, %{}}

      schema_fields ->
        find_matching_schema_attrs(schema_fields, attrs)
    end
  end

  defp find_matching_schema_attrs(schema_fields, attrs) do
    schema_field_names = schema_fields |> Keyword.keys() |> Enum.map(&to_string/1)
    top_level_attrs = Map.drop(attrs, @core_cloudevents_fields)

    matching_attrs =
      top_level_attrs
      |> Enum.filter(fn {key, _value} -> key in schema_field_names end)
      |> Map.new()

    if Enum.empty?(matching_attrs), do: {false, %{}}, else: {true, matching_attrs}
  end
end
