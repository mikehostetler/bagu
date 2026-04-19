defmodule Jido.Signal.TraceContext do
  @moduledoc """
  Process-dictionary-based trace context management.

  Stores current trace context in the process dictionary so it can be
  accessed when creating new signals without explicit parameter passing.

  ## Usage Pattern

  1. **Ingress**: When receiving a signal, set context from the signal
  2. **Processing**: Access context when creating outbound signals
  3. **Egress**: Clear context when done

  ## Examples

      # At ingress point (e.g., AgentServer.handle_call)
      {signal, ctx} = TraceContext.ensure_from_signal(signal)

      # During processing - context available automatically
      ctx = TraceContext.current()

      # When emitting signals, propagate trace as child
      {:ok, traced_signal} = TraceContext.propagate_to(outbound_signal, input_signal.id)

      # At egress
      TraceContext.clear()

  ## Thread Safety

  Process dictionary is per-process, so context is automatically isolated.
  For Task.async or spawn, context must be explicitly passed and restored.

  ## Example: Spawning with Context

      # Capture context before spawning
      ctx = TraceContext.current()

      Task.async(fn ->
        # Restore context in spawned process
        TraceContext.set(ctx)

        # Now context is available in the spawned task
        TraceContext.current()
      end)

  ## See Also

  * `Jido.Signal.Trace` - Low-level trace context creation and manipulation
  * `Jido.Signal.Trace.Context` - The trace context struct
  * `Jido.Signal.Ext.Trace` - The trace extension for signals
  """

  alias Jido.Signal
  alias Jido.Signal.Trace
  alias Jido.Signal.Trace.Context

  @trace_context_key :jido_trace_context

  @doc """
  Gets the current trace context from the process dictionary.

  Returns `nil` if no context is set.

  ## Examples

      iex> TraceContext.current()
      nil

      iex> TraceContext.set(ctx)
      iex> TraceContext.current()
      %Context{trace_id: "abc123", span_id: "def456"}
  """
  @spec current() :: Context.t() | nil
  def current do
    Process.get(@trace_context_key)
  end

  @doc """
  Sets the trace context in the process dictionary.

  Returns `:ok`.

  ## Examples

      iex> TraceContext.set(ctx)
      :ok
  """
  @spec set(Context.t()) :: :ok
  def set(%Context{} = context) do
    Process.put(@trace_context_key, context)
    :ok
  end

  @doc """
  Clears the trace context from the process dictionary.

  Returns `:ok`.

  ## Examples

      iex> TraceContext.set(ctx)
      iex> TraceContext.clear()
      :ok
      iex> TraceContext.current()
      nil
  """
  @spec clear() :: :ok
  def clear do
    Process.delete(@trace_context_key)
    :ok
  end

  @doc """
  Sets trace context from a signal's extension data.

  Extracts trace context from the signal's `correlation` extension
  and sets it in the process dictionary.

  Returns `:ok` if context was set, `:error` if signal has no trace.

  ## Examples

      :ok = TraceContext.set_from_signal(traced_signal)
  """
  @spec set_from_signal(Signal.t()) :: :ok | :error
  def set_from_signal(%Signal{} = signal) do
    case Trace.get(signal) do
      nil -> :error
      ctx -> set(ctx)
    end
  end

  @doc """
  Ensures trace context is set from a signal.

  If the signal has trace context, extracts and sets it.
  If not, creates a new root trace, adds it to the signal, and sets it.

  Returns `{signal, trace_context}` where signal may be updated with trace.

  ## Options

  - `:causation_id` - Optional causation reference for new root traces
  - `:tracestate` - Optional W3C tracestate for new root traces

  ## Examples

      # Signal without trace - creates new root
      {traced_signal, ctx} = TraceContext.ensure_from_signal(signal)

      # Signal with trace - uses existing
      {signal, ctx} = TraceContext.ensure_from_signal(traced_signal)
  """
  @spec ensure_from_signal(Signal.t(), keyword()) :: {Signal.t(), Context.t()}
  def ensure_from_signal(%Signal{} = signal, opts \\ []) do
    {:ok, traced_signal, ctx} = Trace.ensure(signal, opts)
    set(ctx)
    {traced_signal, ctx}
  end

  @doc """
  Builds child context from current process context.

  If there's a current trace context, creates a child span linked to it.
  If no current context, creates a new root trace.

  ## Examples

      # With existing context - creates child
      TraceContext.set(parent_ctx)
      child = TraceContext.child_context("input-signal-id")
      child.trace_id #=> parent_ctx.trace_id (inherited)
      child.parent_span_id #=> parent_ctx.span_id (linked)

      # Without context - creates root
      TraceContext.clear()
      root = TraceContext.child_context("input-signal-id")
      root.parent_span_id #=> nil
  """
  @spec child_context(String.t() | nil) :: Context.t()
  def child_context(causation_id \\ nil) do
    case current() do
      nil -> Trace.new_root(causation_id: causation_id)
      parent -> Trace.child_of(parent, causation_id)
    end
  end

  @doc """
  Adds current trace context as child to an outbound signal.

  Creates a child span linked to the current process context
  and adds it to the signal.

  ## Examples

      # Set up parent context
      TraceContext.set(parent_ctx)

      # Create outbound signal
      {:ok, signal} = Signal.new("user.created", %{user_id: "123"})

      # Propagate trace as child
      {:ok, traced} = TraceContext.propagate_to(signal, "input-signal-id")
      Trace.get(traced).trace_id #=> parent_ctx.trace_id (inherited)
      Trace.get(traced).parent_span_id #=> parent_ctx.span_id (linked)
      Trace.get(traced).causation_id #=> "input-signal-id"
  """
  @spec propagate_to(Signal.t(), String.t() | nil) :: {:ok, Signal.t()} | {:error, term()}
  def propagate_to(%Signal{} = signal, causation_id \\ nil) do
    ctx = child_context(causation_id)
    Trace.put(signal, ctx)
  end

  @doc """
  Converts current trace context to metadata map for telemetry/observability.

  Returns a flat map with `jido_` prefixed keys suitable for telemetry metadata.

  ## Examples

      TraceContext.set(ctx)
      TraceContext.to_telemetry_metadata()
      #=> %{
      #=>   jido_trace_id: "abc",
      #=>   jido_span_id: "def",
      #=>   jido_parent_span_id: "parent",
      #=>   jido_causation_id: nil
      #=> }
  """
  @spec to_telemetry_metadata() :: map()
  def to_telemetry_metadata do
    Context.to_telemetry_metadata(current())
  end

  @doc """
  Converts a trace context to metadata map for telemetry/observability.

  ## Examples

      TraceContext.to_telemetry_metadata(ctx)
      #=> %{jido_trace_id: "abc", jido_span_id: "def", ...}

      TraceContext.to_telemetry_metadata(nil)
      #=> %{jido_trace_id: nil, jido_span_id: nil, ...}
  """
  @spec to_telemetry_metadata(Context.t() | nil) :: map()
  def to_telemetry_metadata(ctx) do
    Context.to_telemetry_metadata(ctx)
  end

  @doc """
  Wraps a function with trace context preservation.

  Sets context from the signal or context before executing the function,
  and clears it after (even if the function raises).

  ## Examples

      # With a signal
      result = TraceContext.with_context(traced_signal, fn ->
        # Context is available here
        ctx = TraceContext.current()
        # ... do work ...
        :result
      end)
      # Context is cleared after

      # With explicit context
      result = TraceContext.with_context(ctx, fn ->
        TraceContext.current() #=> ctx
        :result
      end)
  """
  @spec with_context(Signal.t() | Context.t(), (-> result)) :: result
        when result: term()
  def with_context(context_or_signal, fun)

  def with_context(%Signal{} = signal, fun) when is_function(fun, 0) do
    {_traced_signal, _ctx} = ensure_from_signal(signal)

    try do
      fun.()
    after
      clear()
    end
  end

  def with_context(%Context{} = ctx, fun) when is_function(fun, 0) do
    set(ctx)

    try do
      fun.()
    after
      clear()
    end
  end

  @doc """
  Ensures trace context is set from a state map containing a current_signal.

  This is a convenience for extracting trace from agent state patterns
  that store the current signal being processed.

  Returns `:ok` if context was set, `:error` if no signal or no trace.

  ## Examples

      state = %{current_signal: traced_signal, other: :data}
      :ok = TraceContext.ensure_set_from_state(state)
  """
  @spec ensure_set_from_state(map()) :: :ok | :error
  def ensure_set_from_state(%{current_signal: %Signal{} = signal}) do
    case Trace.get(signal) do
      nil -> :error
      ctx -> set(ctx)
    end
  end

  def ensure_set_from_state(%{current_signal: nil}), do: :ok
  def ensure_set_from_state(_state), do: :ok
end
