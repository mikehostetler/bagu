defmodule Jido.Signal.Trace.Context do
  @moduledoc """
  Trace context struct for distributed tracing.

  Represents W3C Trace Context compatible trace information that can be
  propagated across signal boundaries.

  ## Fields

  - `trace_id` - 32 hex chars (128-bit) shared across entire workflow
  - `span_id` - 16 hex chars (64-bit) unique to this signal
  - `parent_span_id` - Parent's span_id for hierarchy linkage (optional)
  - `causation_id` - ID of the signal that caused this one (optional)
  - `tracestate` - W3C tracestate for vendor-specific data (optional)

  ## W3C Trace Context Compatibility

  IDs are generated in W3C-compatible format:
  - trace_id: 32 hex chars (128-bit)
  - span_id: 16 hex chars (64-bit)

  ## Examples

      # Create a new root context
      {:ok, ctx} = Context.new()

      # Create with causation
      {:ok, ctx} = Context.new(causation_id: "external-123")

      # Create a child context
      {:ok, child} = Context.child_of(parent_ctx, "parent-signal-id")
  """

  @trace_id_bytes 16
  @span_id_bytes 8

  @context_schema Zoi.struct(
                    __MODULE__,
                    %{
                      trace_id: Zoi.string(),
                      span_id: Zoi.string(),
                      parent_span_id: Zoi.string() |> Zoi.nullable() |> Zoi.optional(),
                      causation_id: Zoi.string() |> Zoi.nullable() |> Zoi.optional(),
                      tracestate: Zoi.string() |> Zoi.nullable() |> Zoi.optional()
                    }
                  )

  @type t :: unquote(Zoi.type_spec(@context_schema))
  @enforce_keys Zoi.Struct.enforce_keys(@context_schema)
  defstruct Zoi.Struct.struct_fields(@context_schema)

  @doc "Returns the Zoi schema for Context"
  def schema, do: @context_schema

  @doc """
  Creates a new root trace context.

  Generates new W3C-compatible trace_id (32 hex chars) and span_id (16 hex chars).

  ## Options

  - `:causation_id` - Optional causation reference (e.g., external request ID)
  - `:tracestate` - Optional W3C tracestate string for vendor-specific data

  ## Examples

      {:ok, ctx} = Context.new()
      {:ok, ctx} = Context.new(causation_id: "external-123")
      {:ok, ctx} = Context.new(tracestate: "vendor1=value1")
  """
  @spec new(keyword()) :: {:ok, t()}
  def new(opts \\ []) do
    {:ok,
     %__MODULE__{
       trace_id: generate_trace_id(),
       span_id: generate_span_id(),
       parent_span_id: nil,
       causation_id: opts[:causation_id],
       tracestate: opts[:tracestate]
     }}
  end

  @doc """
  Creates a new root trace context, raising on error.

  ## Examples

      ctx = Context.new!()
  """
  @spec new!(keyword()) :: t()
  def new!(opts \\ []) do
    {:ok, ctx} = new(opts)
    ctx
  end

  @doc """
  Creates a child trace context that continues the parent's trace.

  The child:
  - Shares the parent's `trace_id`
  - Gets a new unique `span_id`
  - Sets `parent_span_id` to the parent's `span_id`
  - Sets `causation_id` to the causing signal's ID
  - Inherits `tracestate`

  ## Examples

      {:ok, child} = Context.child_of(parent_ctx, parent_signal.id)
  """
  @spec child_of(t(), String.t() | nil) :: {:ok, t()}
  def child_of(%__MODULE__{trace_id: tid, span_id: parent_sid} = parent, causation_id) do
    {:ok,
     %__MODULE__{
       trace_id: tid,
       span_id: generate_span_id(),
       parent_span_id: parent_sid,
       causation_id: causation_id,
       tracestate: parent.tracestate
     }}
  end

  def child_of(nil, causation_id) do
    new(causation_id: causation_id)
  end

  @doc """
  Creates a child trace context, raising on error.

  ## Examples

      child = Context.child_of!(parent_ctx, "signal-id")
  """
  @spec child_of!(t() | nil, String.t() | nil) :: t()
  def child_of!(parent, causation_id) do
    {:ok, ctx} = child_of(parent, causation_id)
    ctx
  end

  @doc """
  Formats trace context as W3C `traceparent` header value.

  Format: `{version}-{trace-id}-{span-id}-{flags}`

  Version is always "00" (current W3C spec).
  Flags is "01" (sampled).

  ## Examples

      Context.to_traceparent(ctx)
      #=> "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
  """
  @spec to_traceparent(t()) :: String.t()
  def to_traceparent(%__MODULE__{trace_id: tid, span_id: sid}) do
    "00-#{tid}-#{sid}-01"
  end

  @doc """
  Parses a W3C `traceparent` header into trace context.

  Returns `{:ok, context}` on success, `{:error, reason}` on failure.

  ## Examples

      {:ok, ctx} = Context.from_traceparent("00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01")
  """
  @spec from_traceparent(String.t()) :: {:ok, t()} | {:error, :invalid_traceparent}
  def from_traceparent(traceparent) when is_binary(traceparent) do
    case String.split(traceparent, "-", trim: true) do
      [_version, trace_id, span_id, _flags]
      when byte_size(trace_id) == 32 and byte_size(span_id) == 16 ->
        if valid_hex?(trace_id) and valid_hex?(span_id) do
          {:ok,
           %__MODULE__{
             trace_id: trace_id,
             span_id: span_id,
             parent_span_id: nil,
             causation_id: nil,
             tracestate: nil
           }}
        else
          {:error, :invalid_traceparent}
        end

      _ ->
        {:error, :invalid_traceparent}
    end
  end

  def from_traceparent(_), do: {:error, :invalid_traceparent}

  @doc """
  Parses a W3C `traceparent` header and creates a child context.

  This is useful when receiving an external request with trace headers
  and you want to create a new span as a child of that trace.

  ## Options

  - `:causation_id` - Optional causation ID for the child span
  - `:tracestate` - Optional tracestate to associate with the child

  ## Examples

      {:ok, child} = Context.child_from_traceparent(
        "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01",
        causation_id: "http-request-123"
      )
  """
  @spec child_from_traceparent(String.t(), keyword()) ::
          {:ok, t()} | {:error, :invalid_traceparent}
  def child_from_traceparent(traceparent, opts \\ []) do
    case from_traceparent(traceparent) do
      {:error, reason} ->
        {:error, reason}

      {:ok, parent_ctx} ->
        {:ok,
         %__MODULE__{
           trace_id: parent_ctx.trace_id,
           span_id: generate_span_id(),
           parent_span_id: parent_ctx.span_id,
           causation_id: opts[:causation_id],
           tracestate: opts[:tracestate]
         }}
    end
  end

  @doc """
  Checks if a trace context is valid.

  A valid trace context has:
  - `trace_id` that is 32 lowercase hex characters
  - `span_id` that is 16 lowercase hex characters

  ## Examples

      Context.valid?(ctx) #=> true
      Context.valid?(nil) #=> false
  """
  @spec valid?(t() | nil) :: boolean()
  def valid?(nil), do: false

  def valid?(%__MODULE__{trace_id: tid, span_id: sid}) when is_binary(tid) and is_binary(sid) do
    byte_size(tid) == 32 and byte_size(sid) == 16 and
      valid_hex?(tid) and valid_hex?(sid)
  end

  def valid?(_), do: false

  @doc """
  Converts the context to a map, filtering out nil values.

  Useful for storing in signal extensions where nil values may not be allowed.

  ## Examples

      Context.to_map(ctx)
      #=> %{trace_id: "abc...", span_id: "def..."}
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = ctx) do
    ctx
    |> Map.from_struct()
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc """
  Creates a context from a map.

  ## Examples

      {:ok, ctx} = Context.from_map(%{trace_id: "abc...", span_id: "def..."})
  """
  @spec from_map(map()) :: {:ok, t()} | {:error, term()}
  def from_map(%{trace_id: tid, span_id: sid} = map) when is_binary(tid) and is_binary(sid) do
    {:ok,
     %__MODULE__{
       trace_id: tid,
       span_id: sid,
       parent_span_id: map[:parent_span_id],
       causation_id: map[:causation_id],
       tracestate: map[:tracestate]
     }}
  end

  def from_map(%{"trace_id" => tid, "span_id" => sid} = map)
      when is_binary(tid) and is_binary(sid) do
    {:ok,
     %__MODULE__{
       trace_id: tid,
       span_id: sid,
       parent_span_id: map["parent_span_id"],
       causation_id: map["causation_id"],
       tracestate: map["tracestate"]
     }}
  end

  def from_map(_), do: {:error, :invalid_map}

  @doc """
  Creates a context from a map, raising on error.

  ## Examples

      ctx = Context.from_map!(%{trace_id: "abc...", span_id: "def..."})
  """
  @spec from_map!(map()) :: t()
  def from_map!(map) do
    case from_map(map) do
      {:ok, ctx} -> ctx
      {:error, reason} -> raise "Failed to create context: #{inspect(reason)}"
    end
  end

  @doc """
  Converts context to telemetry metadata with jido_ prefixed keys.

  ## Examples

      Context.to_telemetry_metadata(ctx)
      #=> %{jido_trace_id: "abc...", jido_span_id: "def...", ...}
  """
  @spec to_telemetry_metadata(t() | nil) :: map()
  def to_telemetry_metadata(nil) do
    %{
      jido_trace_id: nil,
      jido_span_id: nil,
      jido_parent_span_id: nil,
      jido_causation_id: nil
    }
  end

  def to_telemetry_metadata(%__MODULE__{} = ctx) do
    %{
      jido_trace_id: ctx.trace_id,
      jido_span_id: ctx.span_id,
      jido_parent_span_id: ctx.parent_span_id,
      jido_causation_id: ctx.causation_id
    }
  end

  # Generate a W3C-compatible trace ID (128-bit, 32 hex chars)
  defp generate_trace_id do
    :crypto.strong_rand_bytes(@trace_id_bytes) |> Base.encode16(case: :lower)
  end

  # Generate a W3C-compatible span ID (64-bit, 16 hex chars)
  defp generate_span_id do
    :crypto.strong_rand_bytes(@span_id_bytes) |> Base.encode16(case: :lower)
  end

  # Validate that a string contains only lowercase hex characters
  defp valid_hex?(str) when is_binary(str) do
    String.match?(str, ~r/^[0-9a-f]+$/)
  end
end
