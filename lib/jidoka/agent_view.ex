defmodule Jidoka.AgentView do
  @moduledoc """
  Least-common-denominator view contract for a Jidoka agent.

  An `AgentView` is not a Phoenix view and does not render UI. It is the
  application-facing adapter between an agent runtime and any interaction
  surface: LiveView, controllers, CLI sessions, tests, channels, or jobs.

  `Jidoka.Agent.View` remains the low-level projection from `Jido.Thread` and
  strategy state. `Jidoka.AgentView` adds the app-specific pieces that every
  surface needs:

  - choosing the agent module
  - deriving a stable conversation id
  - deriving a stable runtime agent id
  - building runtime context
  - starting or reusing the agent
  - exposing visible messages, streaming drafts, LLM context, and debug events
  - mapping runtime results into a surface-neutral view state
  """

  alias Jido.AI.Request

  @type input :: term()
  @type status :: :idle | :running | :error | :interrupted | :handoff

  defmodule Run do
    @moduledoc """
    In-flight AgentView turn handle.

    The request server may differ from the originally supplied agent when
    conversation handoff routing is active, so callers should use this run
    handle for refresh and completion projection.
    """

    alias Jido.AI.Request

    @type t :: %__MODULE__{
            request: Request.Handle.t(),
            agent_ref: Request.server(),
            request_id: String.t(),
            conversation_id: String.t(),
            view_module: module(),
            input: term(),
            metadata: map()
          }

    @enforce_keys [:request, :agent_ref, :request_id, :conversation_id, :view_module, :input]
    defstruct [:request, :agent_ref, :request_id, :conversation_id, :view_module, :input, metadata: %{}]
  end

  @type t :: %__MODULE__{
          agent_id: String.t(),
          conversation_id: String.t(),
          runtime_context: map(),
          visible_messages: [map()],
          streaming_message: map() | nil,
          llm_context: [map()],
          events: [map()],
          status: status(),
          error: term() | nil,
          error_text: String.t() | nil,
          outcome: term() | nil,
          metadata: map()
        }

  defstruct agent_id: "agent-default",
            conversation_id: "default",
            runtime_context: %{},
            visible_messages: [],
            streaming_message: nil,
            llm_context: [],
            events: [],
            status: :idle,
            error: nil,
            error_text: nil,
            outcome: nil,
            metadata: %{}

  @callback prepare(input()) :: :ok | {:error, term()}
  @callback agent_module(input()) :: module()
  @callback conversation_id(input()) :: String.t()
  @callback agent_id(input()) :: String.t()
  @callback runtime_context(input()) :: map()

  defmacro __using__(opts \\ []) do
    agent = Keyword.get(opts, :agent)

    quote bind_quoted: [agent: agent] do
      @behaviour Jidoka.AgentView

      @jidoka_agent_view_agent agent

      @impl Jidoka.AgentView
      def prepare(_input), do: :ok

      @impl Jidoka.AgentView
      def agent_module(_input) do
        case @jidoka_agent_view_agent do
          nil ->
            raise ArgumentError,
                  "#{inspect(__MODULE__)} must pass `agent:` to `use Jidoka.AgentView` or override agent_module/1"

          module ->
            module
        end
      end

      @impl Jidoka.AgentView
      def conversation_id(input), do: Jidoka.AgentView.default_conversation_id(input)

      @impl Jidoka.AgentView
      def agent_id(input), do: Jidoka.AgentView.default_agent_id(agent_module(input), conversation_id(input))

      @impl Jidoka.AgentView
      def runtime_context(input), do: Jidoka.AgentView.default_runtime_context(input, conversation_id(input))

      @spec start_agent(Jidoka.AgentView.input()) :: {:ok, pid()} | {:error, term()}
      def start_agent(input), do: Jidoka.AgentView.start_agent(__MODULE__, input)

      @spec snapshot(Request.server(), Jidoka.AgentView.input(), keyword()) ::
              {:ok, Jidoka.AgentView.t()} | {:error, term()}
      def snapshot(agent_ref, input, opts \\ []), do: Jidoka.AgentView.snapshot(__MODULE__, agent_ref, input, opts)

      @spec before_turn(Jidoka.AgentView.t(), String.t()) :: Jidoka.AgentView.t()
      def before_turn(view, message), do: Jidoka.AgentView.before_turn(view, message)

      @spec start_turn(pid(), String.t(), Jidoka.AgentView.input(), keyword()) ::
              {:ok, Jidoka.AgentView.Run.t()} | {:error, term()}
      def start_turn(pid, message, input, opts \\ []) do
        Jidoka.AgentView.start_turn(__MODULE__, pid, message, input, opts)
      end

      @spec await_turn(Jidoka.AgentView.Run.t(), keyword()) ::
              {:ok, term()}
              | {:interrupt, Jidoka.Interrupt.t()}
              | {:handoff, Jidoka.Handoff.t()}
              | {:error, term()}
      def await_turn(run, opts \\ []) do
        Jidoka.AgentView.await_turn(__MODULE__, run, opts)
      end

      @spec refresh_turn(Jidoka.AgentView.Run.t(), Jidoka.AgentView.t()) ::
              {:ok, Jidoka.AgentView.t()} | {:error, term()}
      def refresh_turn(run, current_view) do
        Jidoka.AgentView.refresh_turn(__MODULE__, run, current_view)
      end

      @spec after_turn(Jidoka.AgentView.Run.t(), term()) :: {:ok, Jidoka.AgentView.t()} | {:error, term()}
      def after_turn(run, result), do: Jidoka.AgentView.after_turn(__MODULE__, run, result)

      @spec before_submit(Jidoka.AgentView.t(), String.t()) :: Jidoka.AgentView.t()
      def before_submit(view, message), do: before_turn(view, message)

      @spec start_message(pid(), String.t(), Jidoka.AgentView.input(), keyword()) ::
              {:ok, Jidoka.AgentView.Run.t()} | {:error, term()}
      def start_message(pid, message, input, opts \\ []), do: start_turn(pid, message, input, opts)

      @spec await_message(pid(), Jidoka.AgentView.Run.t() | Request.Handle.t(), keyword()) ::
              {:ok, term()}
              | {:interrupt, Jidoka.Interrupt.t()}
              | {:handoff, Jidoka.Handoff.t()}
              | {:error, term()}
      def await_message(pid, run_or_request, opts \\ []) do
        Jidoka.AgentView.await_message(__MODULE__, pid, run_or_request, opts)
      end

      @spec refresh_running(pid(), Jidoka.AgentView.input(), Jidoka.AgentView.t()) ::
              {:ok, Jidoka.AgentView.t()} | {:error, term()}
      def refresh_running(pid, input, current_view) do
        Jidoka.AgentView.refresh_running(__MODULE__, pid, input, current_view)
      end

      @spec after_result(pid(), Jidoka.AgentView.input(), term()) :: {:ok, Jidoka.AgentView.t()} | {:error, term()}
      def after_result(pid, input, result), do: Jidoka.AgentView.after_result(__MODULE__, pid, input, result)

      @spec visible_messages(Jidoka.AgentView.t()) :: [map()]
      def visible_messages(view), do: Jidoka.AgentView.visible_messages(view)

      @spec lifecycle_hooks() :: [atom()]
      def lifecycle_hooks, do: Jidoka.AgentView.lifecycle_hooks()

      @spec ui_hooks() :: [atom()]
      def ui_hooks, do: lifecycle_hooks()

      @spec request_id() :: String.t()
      def request_id, do: Jidoka.AgentView.request_id()

      defoverridable prepare: 1,
                     agent_module: 1,
                     conversation_id: 1,
                     agent_id: 1,
                     runtime_context: 1
    end
  end

  @doc """
  Builds an AgentView struct from attributes.
  """
  @spec new(map() | keyword()) :: t()
  def new(attrs \\ %{}) do
    attrs =
      if Keyword.keyword?(attrs) do
        Map.new(attrs)
      else
        attrs
      end

    struct(__MODULE__, attrs)
  end

  @doc """
  Starts or reuses the agent for `view_module` and `input`.
  """
  @spec start_agent(module(), input()) :: {:ok, pid()} | {:error, term()}
  def start_agent(view_module, input) when is_atom(view_module) do
    with :ok <- prepare_view(view_module, input) do
      agent_id = view_module.agent_id(input)
      agent = view_module.agent_module(input)

      with_start_lock(view_module, agent_id, fn ->
        case Jidoka.whereis(agent_id) do
          nil -> start_or_reuse_agent(agent, agent_id)
          pid -> {:ok, pid}
        end
      end)
    end
  end

  @doc """
  Projects the running agent into a surface-neutral AgentView struct.
  """
  @spec snapshot(module(), Request.server(), input(), keyword()) :: {:ok, t()} | {:error, term()}
  def snapshot(view_module, agent_ref, input, opts \\ []) when is_atom(view_module) and is_list(opts) do
    with {:ok, projection} <- Jidoka.Agent.View.snapshot(agent_ref, opts) do
      {:ok,
       new(%{
         agent_id: projection_agent_id(projection, view_module, input),
         conversation_id: view_module.conversation_id(input),
         runtime_context: view_module.runtime_context(input),
         visible_messages: projection.visible_messages,
         streaming_message: projection.streaming_message,
         llm_context: projection.llm_context,
         events: projection.events,
         status: :idle,
         error: nil,
         error_text: nil,
         outcome: nil,
         metadata: snapshot_metadata(projection, view_module, agent_ref, input, opts)
       })}
    end
  end

  @doc """
  Applies optimistic user-message state before an agent turn starts.
  """
  @spec before_turn(t(), String.t()) :: t()
  def before_turn(%__MODULE__{} = view, message) when is_binary(message) do
    content = String.trim(message)

    if content == "" do
      %{view | status: :idle}
    else
      pending = %{
        id: "pending-" <> Integer.to_string(System.unique_integer([:positive, :monotonic])),
        seq: -1,
        role: :user,
        content: content,
        pending?: true
      }

      %{
        view
        | visible_messages: view.visible_messages ++ [pending],
          streaming_message: nil,
          status: :running,
          error: nil,
          error_text: nil,
          outcome: nil
      }
    end
  end

  @doc """
  Compatibility alias for `before_turn/2`.
  """
  @spec before_submit(t(), String.t()) :: t()
  def before_submit(%__MODULE__{} = view, message) when is_binary(message), do: before_turn(view, message)

  @doc """
  Starts a non-blocking agent turn.
  """
  @spec start_turn(module(), pid(), String.t(), input(), keyword()) :: {:ok, Run.t()} | {:error, term()}
  def start_turn(view_module, pid, message, input, opts \\ [])
      when is_atom(view_module) and is_pid(pid) and is_binary(message) and is_list(opts) do
    case String.trim(message) do
      "" ->
        {:error, Jidoka.Error.validation_error("Message must not be empty.", field: :message)}

      content ->
        with :ok <- prepare_view(view_module, input) do
          chat_opts =
            opts
            |> Keyword.put(:conversation, view_module.conversation_id(input))
            |> Keyword.put(:context, view_module.runtime_context(input))
            |> Keyword.put_new_lazy(:request_id, &request_id/0)
            |> Keyword.put_new(:timeout, 30_000)

          with {:ok, request} <- Jidoka.start_chat_request(pid, content, chat_opts) do
            {:ok, run(view_module, request, input, chat_opts)}
          end
        end
    end
  end

  @doc """
  Compatibility alias for `start_turn/5`.
  """
  @spec start_message(module(), pid(), String.t(), input(), keyword()) :: {:ok, Run.t()} | {:error, term()}
  def start_message(view_module, pid, message, input, opts \\ []),
    do: start_turn(view_module, pid, message, input, opts)

  @doc """
  Awaits an async agent turn and returns the normal public Jidoka chat result.
  """
  @spec await_turn(module(), Run.t(), keyword()) ::
          {:ok, term()}
          | {:interrupt, Jidoka.Interrupt.t()}
          | {:handoff, Jidoka.Handoff.t()}
          | {:error, term()}
  def await_turn(_view_module, %Run{request: request}, opts \\ []) when is_list(opts) do
    Jidoka.await_chat_request(request, timeout: Keyword.get(opts, :timeout, 30_000))
  end

  @doc """
  Compatibility alias for `await_turn/3`.
  """
  @spec await_message(module(), pid(), Run.t() | Request.Handle.t(), keyword()) ::
          {:ok, term()}
          | {:interrupt, Jidoka.Interrupt.t()}
          | {:handoff, Jidoka.Handoff.t()}
          | {:error, term()}
  def await_message(view_module, _pid, %Run{} = run, opts), do: await_turn(view_module, run, opts)

  def await_message(_view_module, _pid, %Request.Handle{} = request, opts) do
    Jidoka.await_chat_request(request, timeout: Keyword.get(opts, :timeout, 30_000))
  end

  @doc """
  Refreshes a running turn while preserving optimistic messages until the thread catches up.
  """
  @spec refresh_turn(module(), Run.t(), t()) :: {:ok, t()} | {:error, term()}
  def refresh_turn(view_module, %Run{} = run, %__MODULE__{} = current_view) when is_atom(view_module) do
    with {:ok, view} <- snapshot(view_module, run.agent_ref, run.input, request_id: run.request_id) do
      {:ok,
       %{
         view
         | visible_messages: running_visible_messages(current_view.visible_messages, view.visible_messages),
           status: :running,
           error: nil,
           error_text: nil
       }}
    end
  end

  @doc """
  Compatibility refresh helper for callers that only have a pid.
  """
  @spec refresh_running(module(), pid(), input(), t()) :: {:ok, t()} | {:error, term()}
  def refresh_running(view_module, pid, input, %__MODULE__{} = current_view)
      when is_atom(view_module) and is_pid(pid) do
    refresh_turn(view_module, run(view_module, Request.Handle.new("__compat__", pid, ""), input, []), current_view)
  end

  @doc """
  Re-projects the agent and applies the final public chat result to view state.
  """
  @spec after_turn(module(), Run.t(), term()) :: {:ok, t()} | {:error, term()}
  def after_turn(view_module, %Run{} = run, result) when is_atom(view_module) do
    with {:ok, view} <- snapshot(view_module, run.agent_ref, run.input, request_id: run.request_id) do
      {:ok, apply_result(view, result)}
    end
  end

  @doc """
  Compatibility result helper for callers that only have a pid.
  """
  @spec after_result(module(), pid(), input(), term()) :: {:ok, t()} | {:error, term()}
  def after_result(view_module, pid, input, result) when is_atom(view_module) and is_pid(pid) do
    after_turn(view_module, run(view_module, Request.Handle.new("__compat__", pid, ""), input, []), result)
  end

  @doc """
  Returns visible transcript messages plus the in-flight streaming draft, if any.
  """
  @spec visible_messages(t() | map()) :: [map()]
  def visible_messages(%{visible_messages: messages, streaming_message: nil}), do: messages

  def visible_messages(%{visible_messages: messages, streaming_message: streaming_message}) do
    messages ++ [streaming_message]
  end

  @doc """
  Returns the standard AgentView lifecycle hook names.
  """
  @spec lifecycle_hooks() :: [atom()]
  def lifecycle_hooks, do: [:before_turn, :after_turn, :snapshot]

  @doc """
  Compatibility alias for `lifecycle_hooks/0`.
  """
  @spec ui_hooks() :: [atom()]
  def ui_hooks, do: lifecycle_hooks()

  @doc """
  Generates a request id suitable for view-owned async chat requests.
  """
  @spec request_id() :: String.t()
  def request_id do
    "agent-view-" <> Integer.to_string(System.unique_integer([:positive, :monotonic]))
  end

  @doc """
  Default conversation id derivation for map, keyword, or arbitrary input.
  """
  @spec default_conversation_id(input()) :: String.t()
  def default_conversation_id(input) do
    input
    |> input_value(:conversation_id)
    |> normalize_id("default")
  end

  @doc """
  Default runtime agent id derivation.
  """
  @spec default_agent_id(module(), String.t()) :: String.t()
  def default_agent_id(agent, conversation_id) when is_atom(agent) and is_binary(conversation_id) do
    base =
      if function_exported?(agent, :id, 0) do
        apply(agent, :id, [])
      else
        agent
        |> Module.split()
        |> List.last()
        |> Macro.underscore()
      end

    "#{base}-#{conversation_id}"
  end

  @doc """
  Default runtime context for an agent view.
  """
  @spec default_runtime_context(input(), String.t()) :: map()
  def default_runtime_context(_input, conversation_id), do: %{session: conversation_id}

  @doc """
  Normalizes user/application ids into stable lower snake case.
  """
  @spec normalize_id(term(), String.t()) :: String.t()
  def normalize_id(value, default \\ "default")

  def normalize_id(nil, default), do: default

  def normalize_id(value, default) do
    value
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_]+/, "_")
    |> String.trim("_")
    |> case do
      "" -> default
      id -> id
    end
  end

  defp run(view_module, %Request.Handle{} = request, input, opts) do
    %Run{
      request: request,
      agent_ref: request.server,
      request_id: request.id,
      conversation_id: Keyword.get(opts, :conversation, view_module.conversation_id(input)),
      view_module: view_module,
      input: input,
      metadata: %{timeout: Keyword.get(opts, :timeout, 30_000)}
    }
  end

  defp projection_agent_id(projection, view_module, input) do
    case Map.get(projection, :agent_id) do
      id when is_binary(id) and id != "" -> id
      id when is_atom(id) -> Atom.to_string(id)
      id when not is_nil(id) -> to_string(id)
      _ -> view_module.agent_id(input)
    end
  end

  defp snapshot_metadata(projection, view_module, agent_ref, input, opts) do
    conversation_id = view_module.conversation_id(input)

    %{
      projection: %{
        context_ref: Map.get(projection, :context_ref),
        thread_id: Map.get(projection, :thread_id),
        thread_rev: Map.get(projection, :thread_rev),
        entry_count: Map.get(projection, :entry_count)
      }
    }
    |> maybe_put(:request_summary, latest_request_summary(agent_ref, Keyword.get(opts, :request_id)))
    |> maybe_put(:handoff_owner, Jidoka.handoff_owner(conversation_id))
  end

  defp latest_request_summary(agent_ref, request_id) do
    case Jidoka.inspect_request(agent_ref) do
      {:ok, %{request_id: ^request_id} = summary} when is_binary(request_id) -> summary
      {:ok, summary} when is_nil(request_id) -> summary
      _ -> nil
    end
  rescue
    _error -> nil
  catch
    :exit, _reason -> nil
  end

  defp prepare_view(view_module, input) do
    case view_module.prepare(input) do
      :ok ->
        :ok

      {:error, _reason} = error ->
        error

      other ->
        {:error,
         Jidoka.Error.config_error("AgentView prepare/1 must return :ok or {:error, reason}.",
           value: other
         )}
    end
  end

  defp apply_result(view, {:error, reason}) do
    %{
      view
      | streaming_message: nil,
        status: :error,
        error: reason,
        error_text: Jidoka.format_error(reason),
        outcome: {:error, reason}
    }
  end

  defp apply_result(view, {:interrupt, interrupt}) do
    %{
      view
      | streaming_message: nil,
        status: :interrupted,
        error: nil,
        error_text: interrupt.message,
        outcome: {:interrupt, interrupt}
    }
  end

  defp apply_result(view, {:handoff, handoff}) do
    %{
      view
      | streaming_message: nil,
        status: :handoff,
        error: nil,
        error_text: "Conversation handed off to #{handoff.to_agent_id}.",
        outcome: {:handoff, handoff}
    }
  end

  defp apply_result(view, {:ok, reply}) do
    %{view | streaming_message: nil, status: :idle, error: nil, error_text: nil, outcome: {:ok, reply}}
  end

  defp running_visible_messages(current_messages, refreshed_messages) do
    if refreshed_messages == [] do
      current_messages
    else
      refreshed_messages
    end
  end

  defp start_or_reuse_agent(agent, agent_id) do
    case start_agent_module(agent, agent_id) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, {:already_registered, pid}} when is_pid(pid) ->
        {:ok, pid}

      {:error, _reason} = error ->
        case Jidoka.whereis(agent_id) do
          pid when is_pid(pid) -> {:ok, pid}
          nil -> error
        end
    end
  end

  defp start_agent_module(agent, agent_id) when is_atom(agent) do
    if function_exported?(agent, :start_link, 1) do
      apply(agent, :start_link, [[id: agent_id]])
    else
      Jidoka.start_agent(agent, id: agent_id)
    end
  end

  defp with_start_lock(view_module, agent_id, fun) when is_atom(view_module) and is_binary(agent_id) do
    lock_id = {{__MODULE__, view_module, agent_id}, self()}

    case :global.trans(lock_id, fun, [node()], 5) do
      :aborted -> {:error, Jidoka.Error.execution_error("Could not acquire agent start lock.", agent_id: agent_id)}
      result -> result
    end
  end

  defp input_value(input, key) when is_list(input) and is_atom(key) do
    Keyword.get(input, key)
  end

  defp input_value(%{} = input, key) when is_atom(key) do
    Map.get(input, key, Map.get(input, Atom.to_string(key)))
  end

  defp input_value(_input, _key), do: nil

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, _key, []), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
