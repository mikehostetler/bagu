defmodule Moto.Subagent do
  @moduledoc false

  alias Jido.AI.Request

  @enforce_keys [:agent, :name, :description, :target, :timeout, :forward_context, :result]
  defstruct [:agent, :name, :description, :target, :timeout, :forward_context, :result]

  @type name :: String.t()
  @type target :: :ephemeral | {:peer, String.t()} | {:peer, {:context, atom() | String.t()}}
  @type forward_context ::
          :public | :none | {:only, [atom() | String.t()]} | {:except, [atom() | String.t()]}
  @type result_mode :: :text | :structured
  @type registry :: %{required(name()) => module()}
  @type t :: %__MODULE__{
          agent: module(),
          name: name(),
          description: String.t(),
          target: target(),
          timeout: pos_integer(),
          forward_context: forward_context(),
          result: result_mode()
        }

  @required_functions [
    {:name, 0},
    {:chat, 3},
    {:start_link, 1},
    {:runtime_module, 0}
  ]

  @request_id_key :__moto_request_id__
  @server_key :__moto_server__
  @depth_key :__moto_subagent_depth__
  @request_meta_key :moto_subagents
  @task_schema Zoi.object(%{task: Zoi.string()})
  @text_output_schema Zoi.object(%{result: Zoi.string()})
  @structured_output_schema Zoi.object(%{result: Zoi.string(), subagent: Zoi.map()})
  @default_timeout 30_000
  @default_forward_context :public
  @default_result :text

  @spec task_schema() :: Zoi.schema()
  def task_schema, do: @task_schema

  @spec output_schema(t()) :: Zoi.schema()
  def output_schema(%__MODULE__{result: :structured}), do: @structured_output_schema
  def output_schema(%__MODULE__{}), do: @text_output_schema

  @spec request_id_key() :: atom()
  def request_id_key, do: @request_id_key

  @spec server_key() :: atom()
  def server_key, do: @server_key

  @spec depth_key() :: atom()
  def depth_key, do: @depth_key

  @spec validate_agent_module(module()) :: :ok | {:error, String.t()}
  def validate_agent_module(module) when is_atom(module) do
    cond do
      match?({:error, _}, Code.ensure_compiled(module)) ->
        {:error, "subagent #{inspect(module)} could not be loaded"}

      missing = missing_functions(module) ->
        {:error,
         "subagent #{inspect(module)} is not a valid Moto subagent; missing #{Enum.join(missing, ", ")}"}

      true ->
        agent_name(module)
        |> case do
          {:ok, _name} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  def validate_agent_module(other),
    do: {:error, "subagent entries must be modules, got: #{inspect(other)}"}

  @spec agent_name(module()) :: {:ok, name()} | {:error, String.t()}
  def agent_name(module) when is_atom(module) do
    with :ok <- ensure_compiled_agent(module),
         published_name when is_binary(published_name) <- module.name(),
         trimmed <- String.trim(published_name),
         :ok <- validate_published_name(trimmed, :agent) do
      {:ok, trimmed}
    else
      {:error, reason} ->
        {:error, reason}

      _ ->
        {:error, "subagent #{inspect(module)} must publish a non-empty string name"}
    end
  end

  def agent_name(other),
    do: {:error, "subagent entries must be modules, got: #{inspect(other)}"}

  @spec subagent_names([t()]) :: {:ok, [name()]} | {:error, String.t()}
  def subagent_names(subagents) when is_list(subagents) do
    names = Enum.map(subagents, & &1.name)

    if Enum.uniq(names) == names do
      {:ok, names}
    else
      {:error, "subagent names must be unique within a Moto agent"}
    end
  end

  @spec new(module(), keyword()) :: {:ok, t()} | {:error, String.t()}
  def new(agent_module, opts \\ []) when is_atom(agent_module) and is_list(opts) do
    with :ok <- validate_agent_module(agent_module),
         {:ok, default_name} <- agent_name(agent_module),
         published_name <- Keyword.get(opts, :as) || default_name,
         {:ok, normalized_name} <- normalize_subagent_name(published_name),
         {:ok, description} <-
           normalize_description(
             Keyword.get(opts, :description) ||
               "Ask #{normalized_name} to handle a specialist task."
           ),
         {:ok, target} <- normalize_target(Keyword.get(opts, :target) || :ephemeral),
         {:ok, timeout} <- normalize_timeout(Keyword.get(opts, :timeout, @default_timeout)),
         {:ok, forward_context} <-
           normalize_forward_context(
             Keyword.get(opts, :forward_context, @default_forward_context)
           ),
         {:ok, result} <- normalize_result(Keyword.get(opts, :result, @default_result)) do
      {:ok,
       %__MODULE__{
         agent: agent_module,
         name: normalized_name,
         description: description,
         target: target,
         timeout: timeout,
         forward_context: forward_context,
         result: result
       }}
    end
  end

  @spec normalize_available_subagents([module()] | %{required(name()) => module()}) ::
          {:ok, registry()} | {:error, String.t()}
  def normalize_available_subagents(modules) when is_list(modules) do
    modules
    |> Enum.reduce_while({:ok, %{}}, fn module, {:ok, acc} ->
      with {:ok, name} <- agent_name(module),
           :ok <- ensure_unique_registry_name(name, acc) do
        {:cont, {:ok, Map.put(acc, name, module)}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  def normalize_available_subagents(registry) when is_map(registry) do
    registry
    |> Enum.reduce_while({:ok, %{}}, fn {name, module}, {:ok, acc} ->
      with true <- is_binary(name) or {:error, "subagent registry keys must be strings"},
           trimmed <- String.trim(name),
           :ok <- validate_published_name(trimmed, :agent),
           {:ok, published_name} <- agent_name(module),
           true <-
             trimmed == published_name or
               {:error,
                "subagent registry key #{inspect(trimmed)} must match published agent name #{inspect(published_name)}"},
           :ok <- ensure_unique_registry_name(trimmed, acc) do
        {:cont, {:ok, Map.put(acc, trimmed, module)}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
        false -> {:halt, {:error, "subagent registry keys must be non-empty strings"}}
      end
    end)
  end

  def normalize_available_subagents(other),
    do:
      {:error,
       "available_subagents must be a list of Moto agent modules or a map of name => module, got: #{inspect(other)}"}

  @spec resolve_subagent_name(name(), registry()) :: {:ok, module()} | {:error, String.t()}
  def resolve_subagent_name(name, registry) when is_binary(name) and is_map(registry) do
    case Map.fetch(registry, name) do
      {:ok, module} -> {:ok, module}
      :error -> {:error, "unknown subagent #{inspect(name)}"}
    end
  end

  def resolve_subagent_name(_name, _registry),
    do: {:error, "subagent name must be a string and registry must be a map"}

  @spec tool_module(base_module :: module(), t(), non_neg_integer()) :: module()
  def tool_module(base_module, %__MODULE__{} = subagent, index) do
    suffix =
      subagent.name
      |> String.replace(~r/[^A-Za-z0-9_]/, "_")
      |> Macro.camelize()

    Module.concat(base_module, :"SubagentTool#{suffix}#{index}")
  end

  @spec tool_module_ast(module(), t()) :: Macro.t()
  def tool_module_ast(tool_module, %__MODULE__{} = subagent) do
    quote location: :keep do
      defmodule unquote(tool_module) do
        use Moto.Tool,
          name: unquote(subagent.name),
          description: unquote(subagent.description),
          schema: unquote(Macro.escape(Moto.Subagent.task_schema())),
          output_schema: unquote(Macro.escape(Moto.Subagent.output_schema(subagent)))

        @subagent unquote(Macro.escape(subagent))

        @impl true
        def run(params, context) do
          Moto.Subagent.run_subagent_tool(@subagent, params, context)
        end
      end
    end
  end

  @spec on_before_cmd(Jido.Agent.t(), term()) :: {:ok, Jido.Agent.t(), term()}
  def on_before_cmd(agent, {:ai_react_start, %{request_id: request_id} = params})
      when is_binary(request_id) do
    context = Map.get(params, :tool_context, %{}) || %{}

    context =
      context
      |> Map.put(@request_id_key, request_id)
      |> Map.put(@server_key, self())
      |> Map.put_new(@depth_key, current_depth(context))

    {:ok, agent, {:ai_react_start, Map.put(params, :tool_context, context)}}
  end

  def on_before_cmd(agent, action), do: {:ok, agent, action}

  @spec on_after_cmd(Jido.Agent.t(), term(), [term()]) :: {:ok, Jido.Agent.t(), [term()]}
  def on_after_cmd(agent, {:ai_react_start, %{request_id: request_id}}, directives)
      when is_binary(request_id) do
    subagent_calls = drain_request_meta(self(), request_id)

    if subagent_calls == [] do
      {:ok, agent, directives}
    else
      {:ok, put_request_meta(agent, request_id, %{calls: subagent_calls}), directives}
    end
  end

  def on_after_cmd(agent, _action, directives), do: {:ok, agent, directives}

  @spec run_subagent_tool(t(), map(), map()) :: {:ok, map()} | {:error, term()}
  def run_subagent_tool(%__MODULE__{} = subagent, params, context)
      when is_map(params) and is_map(context) do
    case execute_subagent(subagent, params, context) do
      {:ok, result, metadata} ->
        maybe_record_metadata(context, metadata)
        {:ok, visible_result(subagent, result, metadata)}

      {:error, reason, metadata} ->
        maybe_record_metadata(context, metadata)
        {:error, {:subagent_failed, subagent.name, reason}}
    end
  end

  @spec run_subagent(t(), map(), map()) :: {:ok, String.t()} | {:error, term()}
  def run_subagent(%__MODULE__{} = subagent, params, context)
      when is_map(params) and is_map(context) do
    case execute_subagent(subagent, params, context) do
      {:ok, result, metadata} ->
        maybe_record_metadata(context, metadata)
        {:ok, result}

      {:error, reason, metadata} ->
        maybe_record_metadata(context, metadata)
        {:error, {:subagent_failed, subagent.name, reason}}
    end
  end

  @spec get_request_meta(Jido.Agent.t(), String.t()) :: map() | nil
  def get_request_meta(agent, request_id) when is_binary(request_id) do
    get_in(agent.state, [:requests, request_id, :meta, @request_meta_key])
  end

  def get_request_meta(_agent, _request_id), do: nil

  @doc """
  Returns the recorded subagent calls for a request.

  This prefers persisted request metadata when available, and falls back to the
  transient ETS buffer used during live ReAct runs.
  """
  @spec request_calls(pid() | String.t() | Jido.Agent.t(), String.t()) :: [map()]
  def request_calls(server_or_agent, request_id) when is_binary(request_id) do
    stored_calls = stored_request_calls(server_or_agent, request_id)
    pending_calls = pending_request_calls(server_or_agent, request_id)

    (stored_calls ++ pending_calls)
    |> Enum.sort_by(&Map.get(&1, :sequence, 0))
    |> Enum.uniq_by(&request_call_identity/1)
  end

  def request_calls(_server_or_agent, _request_id), do: []

  @doc """
  Returns the recorded subagent calls for the latest request on a running agent.
  """
  @spec latest_request_calls(pid() | String.t()) :: [map()]
  def latest_request_calls(server_or_id) do
    case Jido.AgentServer.state(server_or_id) do
      {:ok, %{agent: agent}} ->
        case agent.state.last_request_id do
          request_id when is_binary(request_id) -> request_calls(server_or_id, request_id)
          _ -> []
        end

      _ ->
        []
    end
  end

  defp visible_result(%__MODULE__{result: :structured}, result, metadata) do
    %{result: result, subagent: visible_metadata(metadata)}
  end

  defp visible_result(%__MODULE__{}, result, _metadata), do: %{result: result}

  defp visible_metadata(metadata) when is_map(metadata) do
    %{
      name: Map.get(metadata, :name),
      agent: metadata |> Map.get(:agent) |> inspect(),
      mode: Map.get(metadata, :mode),
      target: metadata |> Map.get(:target) |> inspect(),
      child_id: Map.get(metadata, :child_id),
      child_request_id: Map.get(metadata, :child_request_id),
      duration_ms: Map.get(metadata, :duration_ms, 0),
      outcome: visible_outcome(Map.get(metadata, :outcome)),
      task_preview: Map.get(metadata, :task_preview),
      result_preview: Map.get(metadata, :result_preview),
      context_keys: Map.get(metadata, :context_keys, [])
    }
  end

  defp visible_outcome(:ok), do: :ok
  defp visible_outcome({:interrupt, _interrupt}), do: :interrupt
  defp visible_outcome({:error, reason}), do: {:error, inspect(reason)}
  defp visible_outcome(other), do: other

  defp start_child(agent_module, child_id) do
    agent_module.start_link(id: child_id)
    |> normalize_start_result()
  rescue
    error -> {:error, {error.__struct__, Exception.message(error)}}
  catch
    :exit, reason -> {:error, reason}
  end

  defp normalize_start_result({:ok, pid}) when is_pid(pid), do: {:ok, pid}
  defp normalize_start_result({:ok, pid, _info}) when is_pid(pid), do: {:ok, pid}
  defp normalize_start_result({:error, reason}), do: {:error, reason}
  defp normalize_start_result(:ignore), do: {:error, :ignore}
  defp normalize_start_result(other), do: {:error, {:invalid_start_return, other}}

  defp generated_child_id(%__MODULE__{name: name}) do
    unique = System.unique_integer([:positive])
    "moto-subagent-#{name}-#{unique}"
  end

  defp execute_subagent(%__MODULE__{} = subagent, params, context) do
    started_at = System.monotonic_time(:millisecond)

    with {:ok, task} <- fetch_task(params),
         :ok <- ensure_depth_allowed(context) do
      child_context = forwarded_context(context, subagent.forward_context)
      delegate(subagent, task, context, child_context, started_at)
    else
      {:error, reason} ->
        {:error, reason, error_metadata(subagent, reason, context, nil, started_at)}
    end
  end

  defp delegate(
         %__MODULE__{target: :ephemeral} = subagent,
         task,
         _parent_context,
         child_context,
         started_at
       ) do
    child_id = generated_child_id(subagent)

    case start_child(subagent.agent, child_id) do
      {:ok, pid} ->
        try do
          subagent.agent
          |> ask_child(pid, task, child_context, subagent.timeout)
          |> delegate_result(subagent, :ephemeral, task, child_id, child_context, started_at)
        after
          _ = Moto.stop_agent(pid)
        end

      {:error, reason} ->
        reason = {:start_failed, reason}

        {:error, reason,
         error_metadata(subagent, reason, child_context, task, started_at, child_id)}
    end
  end

  defp delegate(
         %__MODULE__{target: {:peer, peer_ref}} = subagent,
         task,
         parent_context,
         child_context,
         started_at
       ) do
    with {:ok, peer_id} <- resolve_peer_id(peer_ref, parent_context),
         {:ok, pid} <- resolve_peer_pid(peer_id),
         :ok <- verify_peer_runtime(subagent.agent, pid) do
      subagent.agent
      |> ask_child(pid, task, child_context, subagent.timeout)
      |> delegate_result(subagent, :peer, task, peer_id, child_context, started_at)
    else
      {:error, reason} ->
        child_id = peer_ref |> peer_ref_preview(parent_context)

        {:error, reason,
         error_metadata(subagent, reason, child_context, task, started_at, child_id)}
    end
  end

  defp ask_child(agent_module, pid, task, context, timeout) do
    if moto_agent_module?(agent_module) do
      ask_moto_child(agent_module, pid, task, context, timeout)
    else
      ask_compatible_child(agent_module, pid, task, context, timeout)
    end
  end

  defp ask_moto_child(agent_module, pid, task, context, timeout) do
    child_opts = [context: context, timeout: timeout]

    with {:ok, prepared_opts} <-
           Moto.Agent.prepare_chat_opts(child_opts, child_chat_config(agent_module)),
         request_opts <-
           Keyword.merge(
             prepared_opts,
             signal_type: "ai.react.query",
             source: "/moto/subagent"
           ),
         {:ok, request} <- Request.create_and_send(pid, task, request_opts) do
      request
      |> await_child_request(agent_module, pid, timeout)
      |> normalize_moto_child_result(pid, request.id, timeout)
    else
      {:error, reason} -> {:error, {:child_error, reason}, nil, %{}}
    end
  end

  defp await_child_request(request, agent_module, pid, timeout) do
    case Request.await(request, timeout: timeout) do
      {:error, :timeout} = result ->
        cancel_child_request(agent_module, pid, request.id)
        result

      result ->
        result
    end
  end

  defp cancel_child_request(agent_module, pid, request_id) when is_binary(request_id) do
    cond do
      function_exported?(agent_module, :runtime_module, 0) ->
        agent_module.runtime_module()
        |> maybe_cancel_child_request(pid, request_id)

      true ->
        maybe_cancel_child_request(agent_module, pid, request_id)
    end
  end

  defp cancel_child_request(_agent_module, _pid, _request_id), do: :ok

  defp maybe_cancel_child_request(module, pid, request_id) when is_atom(module) do
    if function_exported?(module, :cancel, 2) do
      _ = module.cancel(pid, request_id: request_id, reason: :subagent_timeout)
    end

    :ok
  rescue
    _error -> :ok
  catch
    :exit, _reason -> :ok
  end

  defp ask_compatible_child(agent_module, pid, task, context, timeout) do
    task_ref = Task.async(fn -> agent_module.chat(pid, task, context: context) end)

    case Task.yield(task_ref, timeout) do
      {:ok, result} ->
        normalize_direct_child_result(result)

      {:exit, reason} ->
        {:error, {:child_error, reason}, nil, %{}}

      nil ->
        Task.shutdown(task_ref, :brutal_kill)
        {:error, {:timeout, timeout}, nil, %{}}
    end
  end

  defp normalize_moto_child_result({:error, :timeout}, pid, request_id, timeout) do
    {:error, {:timeout, timeout}, request_id, child_request_meta(pid, request_id)}
  end

  defp normalize_moto_child_result(await_result, pid, request_id, _timeout) do
    result =
      pid
      |> Moto.finalize_chat_request(request_id, await_result)
      |> Moto.Hooks.translate_chat_result()

    case result do
      {:ok, child_result} when is_binary(child_result) ->
        {:ok, child_result, request_id, child_request_meta(pid, request_id)}

      {:ok, other} ->
        {:error, {:invalid_result, other}, request_id, child_request_meta(pid, request_id)}

      {:interrupt, interrupt} ->
        {:interrupt, interrupt, request_id, child_request_meta(pid, request_id)}

      {:error, reason} ->
        {:error, {:child_error, reason}, request_id, child_request_meta(pid, request_id)}
    end
  end

  defp normalize_direct_child_result({:ok, result}) when is_binary(result),
    do: {:ok, result, nil, %{}}

  defp normalize_direct_child_result({:ok, other}),
    do: {:error, {:invalid_result, other}, nil, %{}}

  defp normalize_direct_child_result({:interrupt, interrupt}) do
    case normalize_interrupt(interrupt) do
      {:ok, normalized} -> {:interrupt, normalized, nil, %{}}
      {:error, reason} -> {:error, reason, nil, %{}}
    end
  end

  defp normalize_direct_child_result({:error, reason}),
    do: {:error, {:child_error, reason}, nil, %{}}

  defp normalize_direct_child_result(other),
    do: {:error, {:child_error, other}, nil, %{}}

  defp normalize_interrupt(interrupt) do
    {:ok, Moto.Interrupt.new(interrupt)}
  rescue
    _error -> {:error, {:invalid_result, {:interrupt, interrupt}}}
  end

  defp delegate_result(
         {:ok, result, child_request_id, child_result_meta},
         subagent,
         mode,
         task,
         child_id,
         context,
         started_at
       ) do
    {:ok, result,
     call_metadata(
       subagent,
       mode,
       task,
       child_id,
       child_request_id,
       child_result_meta,
       started_at,
       :ok,
       context,
       result
     )}
  end

  defp delegate_result(
         {:error, reason, child_request_id, child_result_meta},
         subagent,
         mode,
         task,
         child_id,
         context,
         started_at
       ) do
    {:error, reason,
     call_metadata(
       subagent,
       mode,
       task,
       child_id,
       child_request_id,
       child_result_meta,
       started_at,
       {:error, reason},
       context,
       nil
     )}
  end

  defp delegate_result(
         {:interrupt, interrupt, child_request_id, child_result_meta},
         subagent,
         mode,
         task,
         child_id,
         context,
         started_at
       ) do
    case normalize_interrupt(interrupt) do
      {:ok, interrupt} ->
        reason = {:child_interrupt, interrupt}

        {:error, reason,
         call_metadata(
           subagent,
           mode,
           task,
           child_id,
           child_request_id,
           child_result_meta,
           started_at,
           {:interrupt, interrupt},
           context,
           nil
         )}

      {:error, reason} ->
        delegate_result(
          {:error, reason, child_request_id, child_result_meta},
          subagent,
          mode,
          task,
          child_id,
          context,
          started_at
        )
    end
  end

  defp child_chat_config(agent_module) do
    default_context =
      if function_exported?(agent_module, :context, 0) do
        agent_module.context()
      else
        %{}
      end

    context_schema =
      if function_exported?(agent_module, :context_schema, 0) do
        agent_module.context_schema()
      else
        nil
      end

    ash =
      cond do
        function_exported?(agent_module, :ash_domain, 0) and
            function_exported?(agent_module, :requires_actor?, 0) ->
          case agent_module.ash_domain() do
            nil -> nil
            domain -> %{domain: domain, require_actor?: agent_module.requires_actor?()}
          end

        true ->
          nil
      end

    %{context: default_context, context_schema: context_schema}
    |> maybe_put_ash(ash)
  end

  defp maybe_put_ash(config, nil), do: config
  defp maybe_put_ash(config, ash), do: Map.put(config, :ash, ash)

  defp moto_agent_module?(agent_module) do
    function_exported?(agent_module, :system_prompt, 0) and
      function_exported?(agent_module, :context, 0) and
      function_exported?(agent_module, :requires_actor?, 0)
  end

  defp child_request_meta(pid, request_id) do
    case Jido.AgentServer.state(pid) do
      {:ok, %{agent: agent}} ->
        case Request.get_request(agent, request_id) do
          nil -> %{}
          request -> %{meta: Map.get(request, :meta, %{}), status: request.status}
        end

      _ ->
        %{}
    end
  end

  defp resolve_peer_id(peer_id, _context) when is_binary(peer_id), do: {:ok, peer_id}

  defp resolve_peer_id({:context, key}, context) when is_atom(key) or is_binary(key) do
    case context_value(context, key) do
      peer_id when is_binary(peer_id) and peer_id != "" -> {:ok, peer_id}
      _ -> {:error, {:peer_not_found, {:context, key}}}
    end
  end

  defp resolve_peer_pid(peer_id) when is_binary(peer_id) do
    case Moto.whereis(peer_id) do
      nil -> {:error, {:peer_not_found, peer_id}}
      pid -> {:ok, pid}
    end
  end

  defp verify_peer_runtime(agent_module, pid) do
    expected_runtime = agent_module.runtime_module()

    case Jido.AgentServer.state(pid) do
      {:ok, %{agent_module: ^expected_runtime}} ->
        :ok

      {:ok, %{agent_module: other}} ->
        {:error, {:peer_mismatch, expected_runtime, other}}

      {:error, reason} ->
        {:error, {:peer_mismatch, expected_runtime, reason}}
    end
  end

  defp fetch_task(%{task: task}) when is_binary(task) do
    case String.trim(task) do
      "" -> {:error, {:invalid_task, :expected_non_empty_string}}
      trimmed -> {:ok, trimmed}
    end
  end

  defp fetch_task(%{"task" => task}) when is_binary(task) do
    case String.trim(task) do
      "" -> {:error, {:invalid_task, :expected_non_empty_string}}
      trimmed -> {:ok, trimmed}
    end
  end

  defp fetch_task(_params), do: {:error, {:invalid_task, :expected_non_empty_string}}

  defp ensure_depth_allowed(context) do
    if current_depth(context) >= 1 do
      {:error, {:recursion_limit, 1}}
    else
      :ok
    end
  end

  defp forwarded_context(context, policy) do
    context
    |> Moto.Context.sanitize_for_subagent()
    |> apply_forward_context_policy(policy)
    |> Map.put(@depth_key, current_depth(context) + 1)
  end

  defp current_depth(context) when is_map(context) do
    case Map.get(context, @depth_key, 0) do
      depth when is_integer(depth) and depth >= 0 -> depth
      _ -> 0
    end
  end

  defp maybe_record_metadata(context, metadata) when is_map(context) and is_map(metadata) do
    parent_server = Map.get(context, @server_key)
    request_id = Map.get(context, @request_id_key)

    if is_pid(parent_server) and is_binary(request_id) do
      Moto.Subagent.Metadata.insert(parent_server, request_id, metadata)
    end

    :ok
  end

  defp maybe_record_metadata(_context, _metadata), do: :ok

  defp drain_request_meta(server, request_id) when is_pid(server) and is_binary(request_id) do
    Moto.Subagent.Metadata.drain(server, request_id)
  end

  defp drain_request_meta(_server, _request_id), do: []

  defp lookup_request_meta(server, request_id) when is_pid(server) and is_binary(request_id) do
    Moto.Subagent.Metadata.lookup(server, request_id)
  end

  defp lookup_request_meta(_server, _request_id), do: []

  defp put_request_meta(agent, request_id, %{calls: calls}) do
    state =
      update_in(agent.state, [:requests, request_id], fn
        nil ->
          nil

        request ->
          existing_calls = get_in(request, [:meta, @request_meta_key, :calls]) || []

          request
          |> Map.put(
            :meta,
            Map.merge(
              Map.get(request, :meta, %{}),
              %{@request_meta_key => %{calls: existing_calls ++ calls}}
            )
          )
      end)

    %{agent | state: state}
  end

  defp call_metadata(
         subagent,
         mode,
         task,
         child_id,
         child_request_id,
         child_result_meta,
         started_at,
         outcome,
         context,
         result
       ) do
    %{
      sequence: next_sequence(),
      name: subagent.name,
      agent: subagent.agent,
      mode: mode,
      target: subagent.target,
      task_preview: task_preview(task),
      child_id: child_id,
      child_request_id: child_request_id,
      duration_ms: System.monotonic_time(:millisecond) - started_at,
      outcome: outcome,
      result_preview: result_preview(result),
      context_keys: context_keys(context),
      child_result_meta: child_result_meta
    }
  end

  defp error_metadata(
         subagent,
         reason,
         context,
         task,
         started_at,
         child_id \\ nil,
         child_result_meta \\ %{}
       ) do
    %{
      sequence: next_sequence(),
      name: subagent.name,
      agent: subagent.agent,
      mode: target_mode(subagent.target),
      target: subagent.target,
      task_preview: task_preview(task),
      child_id: child_id,
      child_request_id: nil,
      duration_ms: System.monotonic_time(:millisecond) - started_at,
      outcome: {:error, reason},
      result_preview: nil,
      context_keys: context_keys(context),
      child_result_meta: child_result_meta
    }
  end

  defp target_mode(:ephemeral), do: :ephemeral
  defp target_mode({:peer, _}), do: :peer

  defp task_preview(task) when is_binary(task) do
    task
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.slice(0, 140)
  end

  defp task_preview(_task), do: nil

  defp result_preview(result) when is_binary(result) do
    result
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.slice(0, 140)
  end

  defp result_preview(_result), do: nil

  defp context_keys(context) when is_map(context) do
    context
    |> Map.drop([@request_id_key, @server_key, @depth_key])
    |> Map.keys()
    |> Enum.map(&key_to_string/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp context_keys(_context), do: []

  defp request_call_identity(%{sequence: sequence}) when is_integer(sequence),
    do: {:sequence, sequence}

  defp request_call_identity(call) when is_map(call) do
    {:fallback, Map.get(call, :name), Map.get(call, :child_request_id), Map.get(call, :child_id)}
  end

  defp next_sequence, do: System.unique_integer([:positive, :monotonic])

  defp stored_request_calls(%Jido.Agent{} = agent, request_id) do
    case get_request_meta(agent, request_id) do
      %{calls: calls} when is_list(calls) -> calls
      _ -> []
    end
  end

  defp stored_request_calls(server, request_id) do
    try do
      case Jido.AgentServer.state(server) do
        {:ok, %{agent: agent}} -> stored_request_calls(agent, request_id)
        _ -> []
      end
    catch
      :exit, _reason -> []
    end
  end

  defp pending_request_calls(server, request_id) when is_pid(server) do
    lookup_request_meta(server, request_id)
  end

  defp pending_request_calls(server_id, request_id) when is_binary(server_id) do
    case Moto.whereis(server_id) do
      nil -> []
      pid -> lookup_request_meta(pid, request_id)
    end
  end

  defp pending_request_calls(_server_or_agent, _request_id), do: []

  defp apply_forward_context_policy(context, :public), do: context
  defp apply_forward_context_policy(_context, :none), do: %{}

  defp apply_forward_context_policy(context, {:only, keys}) when is_list(keys) do
    Enum.reduce(keys, %{}, fn key, acc ->
      case fetch_equivalent_key(context, key) do
        {:ok, actual_key, value} -> Map.put(acc, actual_key, value)
        :error -> acc
      end
    end)
  end

  defp apply_forward_context_policy(context, {:except, keys}) when is_list(keys) do
    Enum.reduce(keys, context, fn key, acc ->
      case fetch_equivalent_key(acc, key) do
        {:ok, actual_key, _value} -> Map.delete(acc, actual_key)
        :error -> acc
      end
    end)
  end

  defp context_value(context, key) when is_map(context) do
    case fetch_equivalent_key(context, key) do
      {:ok, _actual_key, value} -> value
      :error -> nil
    end
  end

  defp fetch_equivalent_key(context, key) when is_map(context) do
    Enum.find_value(context, :error, fn {existing_key, value} ->
      if equivalent_key?(existing_key, key) do
        {:ok, existing_key, value}
      end
    end)
  end

  defp equivalent_key?(left, right), do: key_to_string(left) == key_to_string(right)

  defp peer_ref_preview({:context, key}, context) do
    case context_value(context, key) do
      peer_id when is_binary(peer_id) and peer_id != "" -> peer_id
      _ -> inspect({:context, key})
    end
  end

  defp peer_ref_preview(peer_id, _context) when is_binary(peer_id), do: peer_id

  defp normalize_subagent_name(name) when is_binary(name) do
    trimmed = String.trim(name)

    case validate_published_name(trimmed, :tool) do
      :ok -> {:ok, trimmed}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_subagent_name(other),
    do: {:error, "subagent names must be non-empty strings, got: #{inspect(other)}"}

  defp normalize_description(description) when is_binary(description) do
    trimmed = String.trim(description)

    if trimmed == "" do
      {:error, "subagent descriptions must not be empty"}
    else
      {:ok, trimmed}
    end
  end

  defp normalize_description(other),
    do: {:error, "subagent descriptions must be strings, got: #{inspect(other)}"}

  @spec normalize_target(term()) :: {:ok, target()} | {:error, String.t()}
  def normalize_target(:ephemeral), do: {:ok, :ephemeral}
  def normalize_target("ephemeral"), do: {:ok, :ephemeral}

  def normalize_target({:peer, peer_id}) when is_binary(peer_id) do
    trimmed = String.trim(peer_id)

    if trimmed == "" do
      {:error, "subagent peer ids must not be empty"}
    else
      {:ok, {:peer, trimmed}}
    end
  end

  def normalize_target({:peer, {:context, key}}) when is_atom(key) or is_binary(key) do
    {:ok, {:peer, {:context, key}}}
  end

  def normalize_target(other) do
    {:error,
     "subagent target must be :ephemeral, {:peer, \"id\"}, or {:peer, {:context, key}}, got: #{inspect(other)}"}
  end

  @spec normalize_timeout(term()) :: {:ok, pos_integer()} | {:error, String.t()}
  def normalize_timeout(timeout) when is_integer(timeout) and timeout > 0, do: {:ok, timeout}

  def normalize_timeout(other),
    do:
      {:error,
       "subagent timeout must be a positive integer in milliseconds, got: #{inspect(other)}"}

  @spec normalize_forward_context(term()) :: {:ok, forward_context()} | {:error, String.t()}
  def normalize_forward_context(:public), do: {:ok, :public}
  def normalize_forward_context("public"), do: {:ok, :public}
  def normalize_forward_context(:none), do: {:ok, :none}
  def normalize_forward_context("none"), do: {:ok, :none}

  def normalize_forward_context({mode, keys}) when mode in [:only, :except] do
    normalize_forward_context_keys(mode, keys)
  end

  def normalize_forward_context(%{mode: mode, keys: keys}) do
    mode
    |> normalize_forward_context_mode()
    |> case do
      {:ok, :only} -> normalize_forward_context_keys(:only, keys)
      {:ok, :except} -> normalize_forward_context_keys(:except, keys)
      {:ok, mode} -> {:ok, mode}
      {:error, reason} -> {:error, reason}
    end
  end

  def normalize_forward_context(%{"mode" => mode, "keys" => keys}) do
    normalize_forward_context(%{mode: mode, keys: keys})
  end

  def normalize_forward_context(%{mode: mode}) do
    case normalize_forward_context_mode(mode) do
      {:ok, mode} when mode in [:public, :none] -> {:ok, mode}
      {:ok, mode} -> normalize_forward_context_keys(mode, nil)
      {:error, reason} -> {:error, reason}
    end
  end

  def normalize_forward_context(%{"mode" => mode}) do
    normalize_forward_context(%{mode: mode})
  end

  def normalize_forward_context(other),
    do:
      {:error,
       "subagent forward_context must be :public, :none, {:only, keys}, or {:except, keys}, got: #{inspect(other)}"}

  @spec normalize_result(term()) :: {:ok, result_mode()} | {:error, String.t()}
  def normalize_result(:text), do: {:ok, :text}
  def normalize_result("text"), do: {:ok, :text}
  def normalize_result(:structured), do: {:ok, :structured}
  def normalize_result("structured"), do: {:ok, :structured}

  def normalize_result(other),
    do: {:error, "subagent result must be :text or :structured, got: #{inspect(other)}"}

  defp normalize_forward_context_mode(:public), do: {:ok, :public}
  defp normalize_forward_context_mode("public"), do: {:ok, :public}
  defp normalize_forward_context_mode(:none), do: {:ok, :none}
  defp normalize_forward_context_mode("none"), do: {:ok, :none}
  defp normalize_forward_context_mode(:only), do: {:ok, :only}
  defp normalize_forward_context_mode("only"), do: {:ok, :only}
  defp normalize_forward_context_mode(:except), do: {:ok, :except}
  defp normalize_forward_context_mode("except"), do: {:ok, :except}

  defp normalize_forward_context_mode(other),
    do:
      {:error,
       "subagent forward_context mode must be public, none, only, or except, got: #{inspect(other)}"}

  defp normalize_forward_context_keys(mode, keys) when is_list(keys) do
    keys
    |> Enum.reduce_while({:ok, []}, fn key, {:ok, acc} ->
      case normalize_forward_context_key(key) do
        {:ok, normalized_key} -> {:cont, {:ok, acc ++ [normalized_key]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, normalized_keys} -> {:ok, {mode, normalized_keys}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_forward_context_keys(_mode, other),
    do: {:error, "subagent forward_context keys must be a list, got: #{inspect(other)}"}

  defp normalize_forward_context_key(key) when is_atom(key), do: {:ok, key}

  defp normalize_forward_context_key(key) when is_binary(key) do
    case String.trim(key) do
      "" -> {:error, "subagent forward_context keys must not be empty"}
      trimmed -> {:ok, trimmed}
    end
  end

  defp normalize_forward_context_key(other),
    do: {:error, "subagent forward_context keys must be atoms or strings, got: #{inspect(other)}"}

  defp validate_published_name("", _kind),
    do: {:error, "subagent names must not be empty"}

  defp validate_published_name(name, :tool) do
    if String.match?(name, ~r/^[a-z][a-z0-9_]*$/) do
      :ok
    else
      {:error,
       "subagent tool names must start with a lowercase letter and contain only lowercase letters, numbers, and underscores"}
    end
  end

  defp validate_published_name(name, :agent) do
    if String.match?(name, ~r/^[A-Za-z0-9][A-Za-z0-9_-]*$/) do
      :ok
    else
      {:error,
       "subagent agent names must start with a letter or number and contain only letters, numbers, underscores, and hyphens"}
    end
  end

  defp ensure_compiled_agent(module) do
    cond do
      match?({:error, _}, Code.ensure_compiled(module)) ->
        {:error, "subagent #{inspect(module)} could not be loaded"}

      missing = missing_functions(module) ->
        {:error,
         "subagent #{inspect(module)} is not a valid Moto subagent; missing #{Enum.join(missing, ", ")}"}

      true ->
        :ok
    end
  end

  defp missing_functions(module) do
    @required_functions
    |> Enum.reject(fn {name, arity} -> function_exported?(module, name, arity) end)
    |> Enum.map(fn {name, arity} -> "#{name}/#{arity}" end)
    |> case do
      [] -> nil
      missing -> missing
    end
  end

  defp ensure_unique_registry_name(name, acc) do
    if Map.has_key?(acc, name) do
      {:error, "subagent names must be unique within a Moto subagent registry"}
    else
      :ok
    end
  end

  defp key_to_string(key) when is_atom(key), do: Atom.to_string(key)
  defp key_to_string(key) when is_binary(key), do: key
  defp key_to_string(key), do: inspect(key)
end
