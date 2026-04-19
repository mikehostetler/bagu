defmodule Jido.Signal.Trace do
  @moduledoc """
  Helper functions for distributed trace management.

  Provides utilities for creating and propagating trace contexts
  across signal boundaries. Uses the `correlation` extension
  (Jido.Signal.Ext.Trace) for storage.

  ## Trace Hierarchy

  - `trace_id` - Constant across entire workflow (16-byte hex)
  - `span_id` - Unique per signal (8-byte hex)
  - `parent_span_id` - Links child to parent signal
  - `causation_id` - Signal ID that triggered this signal

  ## W3C Trace Context Compatibility

  IDs are generated in W3C-compatible format:
  - trace_id: 32 hex chars (128-bit)
  - span_id: 16 hex chars (64-bit)

  ## Examples

      # Create a new root trace
      ctx = Jido.Signal.Trace.new_root()

      # Create child context for emitted signal
      child_ctx = Jido.Signal.Trace.child_of(parent_ctx, parent_signal.id)

      # Add trace to signal
      {:ok, traced_signal} = Jido.Signal.Trace.put(signal, ctx)

      # Get trace from signal
      ctx = Jido.Signal.Trace.get(signal)

      # Ensure signal has trace (add root if missing)
      {:ok, signal, ctx} = Jido.Signal.Trace.ensure(signal)
  """

  alias Jido.Signal
  alias Jido.Signal.Trace.Context

  @extension_namespace "correlation"

  @typedoc """
  Trace context struct containing W3C-compatible trace information.
  """
  @type trace_context :: Context.t()

  @doc """
  Creates a new root trace context.

  Generates new W3C-compatible trace_id (32 hex chars) and span_id (16 hex chars).

  ## Options

  - `:causation_id` - Optional causation reference (e.g., external request ID)
  - `:tracestate` - Optional W3C tracestate string for vendor-specific data

  ## Examples

      ctx = Trace.new_root()
      ctx = Trace.new_root(causation_id: "external-123")
      ctx = Trace.new_root(tracestate: "vendor1=value1")
  """
  @spec new_root(keyword()) :: Context.t()
  def new_root(opts \\ []) do
    Context.new!(opts)
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

      parent_ctx = Trace.get(parent_signal)
      child_ctx = Trace.child_of(parent_ctx, parent_signal.id)
  """
  @spec child_of(Context.t() | nil, String.t() | nil) :: Context.t()
  def child_of(parent, causation_id) do
    Context.child_of!(parent, causation_id)
  end

  @doc """
  Extracts trace context from a signal.

  Returns `nil` if the signal has no trace extension.

  ## Examples

      ctx = Trace.get(signal)
      case Trace.get(signal) do
        nil -> "no trace"
        %Context{trace_id: tid} -> "traced: \#{tid}"
      end
  """
  @spec get(Signal.t()) :: Context.t() | nil
  def get(%Signal{} = signal) do
    case Signal.get_extension(signal, @extension_namespace) do
      nil -> nil
      map when is_map(map) -> Context.from_map!(map)
    end
  end

  def get(_), do: nil

  @doc """
  Adds trace context to a signal.

  Uses the `correlation` extension namespace to store trace data.

  ## Examples

      ctx = Trace.new_root()
      {:ok, traced} = Trace.put(signal, ctx)
  """
  @spec put(Signal.t(), Context.t()) :: {:ok, Signal.t()} | {:error, term()}
  def put(%Signal{} = signal, %Context{} = ctx) do
    Signal.put_extension(signal, @extension_namespace, Context.to_map(ctx))
  end

  @doc """
  Adds trace context to a signal, raising on error.

  ## Examples

      traced = Trace.put!(signal, ctx)
  """
  @spec put!(Signal.t(), Context.t()) :: Signal.t()
  def put!(%Signal{} = signal, %Context{} = ctx) do
    case put(signal, ctx) do
      {:ok, s} -> s
      {:error, reason} -> raise "Failed to add trace: #{inspect(reason)}"
    end
  end

  @doc """
  Ensures a signal has trace context.

  If the signal already has a trace, returns it unchanged.
  If not, creates a new root trace and adds it.

  Returns `{:ok, signal, trace_context}`.

  ## Options

  - `:causation_id` - Optional causation reference for new root traces
  - `:tracestate` - Optional W3C tracestate for new root traces

  ## Examples

      {:ok, signal, ctx} = Trace.ensure(signal)
      {:ok, signal, ctx} = Trace.ensure(signal, causation_id: "req-123")
  """
  @spec ensure(Signal.t(), keyword()) :: {:ok, Signal.t(), Context.t()}
  def ensure(%Signal{} = signal, opts \\ []) do
    case get(signal) do
      nil ->
        ctx = new_root(opts)
        {:ok, traced} = put(signal, ctx)
        {:ok, traced, ctx}

      ctx ->
        {:ok, signal, ctx}
    end
  end

  @doc """
  Formats trace context as W3C `traceparent` header value.

  Format: `{version}-{trace-id}-{span-id}-{flags}`

  Version is always "00" (current W3C spec).
  Flags is "01" (sampled).

  ## Examples

      Trace.to_traceparent(ctx)
      #=> "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
  """
  @spec to_traceparent(Context.t()) :: String.t()
  def to_traceparent(%Context{} = ctx) do
    Context.to_traceparent(ctx)
  end

  @doc """
  Parses a W3C `traceparent` header into trace context.

  Returns `nil` if parsing fails (invalid format, wrong lengths).

  ## Examples

      Trace.from_traceparent("00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01")
      #=> %Context{trace_id: "4bf92f3577b34da6a3ce929d0e0e4736", span_id: "00f067aa0ba902b7", ...}

      Trace.from_traceparent("invalid")
      #=> nil
  """
  @spec from_traceparent(String.t()) :: Context.t() | nil
  def from_traceparent(traceparent) when is_binary(traceparent) do
    case Context.from_traceparent(traceparent) do
      {:ok, ctx} -> ctx
      {:error, _} -> nil
    end
  end

  def from_traceparent(_), do: nil

  @doc """
  Parses a W3C `traceparent` header and creates a child context.

  This is useful when receiving an external request with trace headers
  and you want to create a new span as a child of that trace.

  Returns `nil` if parsing fails.

  ## Options

  - `:causation_id` - Optional causation ID for the child span
  - `:tracestate` - Optional tracestate to associate with the child

  ## Examples

      child = Trace.child_from_traceparent(
        "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01",
        causation_id: "http-request-123"
      )
  """
  @spec child_from_traceparent(String.t(), keyword()) :: Context.t() | nil
  def child_from_traceparent(traceparent, opts \\ []) do
    case Context.child_from_traceparent(traceparent, opts) do
      {:ok, ctx} -> ctx
      {:error, _} -> nil
    end
  end

  @doc """
  Checks if a trace context is valid.

  A valid trace context has:
  - `trace_id` that is 32 lowercase hex characters
  - `span_id` that is 16 lowercase hex characters

  ## Examples

      Trace.valid?(ctx) #=> true
      Trace.valid?(nil) #=> false
  """
  @spec valid?(Context.t() | nil) :: boolean()
  def valid?(ctx) do
    Context.valid?(ctx)
  end
end
