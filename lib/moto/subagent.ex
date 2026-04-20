defmodule Moto.Subagent do
  @moduledoc false

  alias Jido.AI.Request

  @enforce_keys [:agent, :name, :description, :target]
  defstruct [:agent, :name, :description, :target]

  @type name :: String.t()
  @type target :: :ephemeral | {:peer, String.t()} | {:peer, {:context, atom() | String.t()}}
  @type registry :: %{required(name()) => module()}
  @type t :: %__MODULE__{
          agent: module(),
          name: name(),
          description: String.t(),
          target: target()
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
  @meta_table :moto_subagent_calls
  @request_meta_key :moto_subagents
  @task_schema Zoi.object(%{task: Zoi.string()})

  @spec task_schema() :: Zoi.schema()
  def task_schema, do: @task_schema

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
         {:ok, target} <- normalize_target(Keyword.get(opts, :target) || :ephemeral) do
      {:ok,
       %__MODULE__{
         agent: agent_module,
         name: normalized_name,
         description: description,
         target: target
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
          output_schema: unquote(Macro.escape(Zoi.object(%{result: Zoi.string()})))

        @subagent unquote(Macro.escape(subagent))

        @impl true
        def run(params, context) do
          case Moto.Subagent.run_subagent(@subagent, params, context) do
            {:ok, result} -> {:ok, %{result: result}}
            other -> other
          end
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

  @spec run_subagent(t(), map(), map()) :: {:ok, String.t()} | {:error, term()}
  def run_subagent(%__MODULE__{} = subagent, params, context)
      when is_map(params) and is_map(context) do
    with {:ok, task} <- fetch_task(params),
         :ok <- ensure_depth_allowed(context) do
      forwarded_context = forwarded_context(context)

      case delegate(subagent, task, forwarded_context) do
        {:ok, result, metadata} ->
          maybe_record_metadata(context, metadata)
          {:ok, result}

        {:error, reason, metadata} ->
          maybe_record_metadata(context, metadata)
          {:error, reason}

        {:interrupt, interrupt, metadata} ->
          maybe_record_metadata(context, metadata)
          {:error, {:subagent_interrupt, subagent.name, interrupt}}

        {:error, reason} ->
          maybe_record_metadata(context, error_metadata(subagent, reason))
          {:error, {:subagent_failed, subagent.name, reason}}
      end
    else
      {:error, reason} ->
        maybe_record_metadata(context, error_metadata(subagent, reason))
        {:error, reason}
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
    |> Enum.uniq()
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

  defp delegate(%__MODULE__{target: :ephemeral} = subagent, task, context) do
    child_id = "moto-subagent-#{System.unique_integer([:positive])}"
    started_at = System.monotonic_time(:millisecond)

    with {:ok, pid} <- subagent.agent.start_link(id: child_id) do
      try do
        case ask_child(subagent.agent, pid, task, context) do
          {:ok, result, child_request_id, child_result_meta} ->
            {:ok, result,
             call_metadata(
               subagent,
               :ephemeral,
               task,
               child_id,
               child_request_id,
               child_result_meta,
               started_at,
               :ok
             )}

          {:error, reason, child_request_id, child_result_meta} ->
            {:error, {:subagent_failed, subagent.name, reason},
             call_metadata(
               subagent,
               :ephemeral,
               task,
               child_id,
               child_request_id,
               child_result_meta,
               started_at,
               {:error, reason}
             )}

          {:interrupt, interrupt, child_request_id, child_result_meta} ->
            {:interrupt, interrupt,
             call_metadata(
               subagent,
               :ephemeral,
               task,
               child_id,
               child_request_id,
               child_result_meta,
               started_at,
               {:interrupt, interrupt}
             )}
        end
      after
        _ = Moto.stop_agent(pid)
      end
    end
  end

  defp delegate(%__MODULE__{target: {:peer, peer_ref}} = subagent, task, context) do
    started_at = System.monotonic_time(:millisecond)

    with {:ok, peer_id} <- resolve_peer_id(peer_ref, context),
         {:ok, pid} <- resolve_peer_pid(peer_id),
         :ok <- verify_peer_runtime(subagent.agent, pid) do
      case ask_child(subagent.agent, pid, task, context) do
        {:ok, result, child_request_id, child_result_meta} ->
          {:ok, result,
           call_metadata(
             subagent,
             :peer,
             task,
             peer_id,
             child_request_id,
             child_result_meta,
             started_at,
             :ok
           )}

        {:error, reason, child_request_id, child_result_meta} ->
          {:error, {:subagent_failed, subagent.name, reason},
           call_metadata(
             subagent,
             :peer,
             task,
             peer_id,
             child_request_id,
             child_result_meta,
             started_at,
             {:error, reason}
           )}

        {:interrupt, interrupt, child_request_id, child_result_meta} ->
          {:interrupt, interrupt,
           call_metadata(
             subagent,
             :peer,
             task,
             peer_id,
             child_request_id,
             child_result_meta,
             started_at,
             {:interrupt, interrupt}
           )}
      end
    end
  end

  defp ask_child(agent_module, pid, task, context) do
    if moto_agent_module?(agent_module) do
      child_opts = [context: context]

      with {:ok, prepared_opts} <-
             Moto.Agent.prepare_chat_opts(child_opts, child_chat_config(agent_module)),
           timeout <- Keyword.get(prepared_opts, :timeout, 30_000),
           request_opts <-
             Keyword.merge(
               prepared_opts,
               signal_type: "ai.react.query",
               source: "/moto/subagent"
             ),
           {:ok, request} <- Request.create_and_send(pid, task, request_opts),
           await_result <- Request.await(request, timeout: timeout) do
        case Moto.finalize_chat_request(pid, request.id, await_result)
             |> Moto.Hooks.translate_chat_result() do
          {:ok, result} when is_binary(result) ->
            {:ok, result, request.id, child_request_meta(pid, request.id)}

          {:ok, other} ->
            {:error, {:invalid_subagent_result, other}, request.id,
             child_request_meta(pid, request.id)}

          {:interrupt, interrupt} ->
            {:interrupt, interrupt, request.id, child_request_meta(pid, request.id)}

          {:error, reason} ->
            {:error, reason, request.id, child_request_meta(pid, request.id)}
        end
      end
    else
      case agent_module.chat(pid, task, context: context) do
        {:ok, result} when is_binary(result) -> {:ok, result, nil, %{}}
        {:ok, other} -> {:error, {:invalid_subagent_result, other}, nil, %{}}
        {:interrupt, interrupt} -> {:interrupt, interrupt, nil, %{}}
        {:error, reason} -> {:error, reason, nil, %{}}
      end
    end
  end

  defp child_chat_config(agent_module) do
    default_context =
      if function_exported?(agent_module, :context, 0) do
        agent_module.context()
      else
        %{}
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

    case ash do
      nil -> %{context: default_context}
      value -> %{context: default_context, ash: value}
    end
  end

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
    case Map.get(context, key, Map.get(context, Atom.to_string(key))) do
      peer_id when is_binary(peer_id) and peer_id != "" -> {:ok, peer_id}
      nil -> {:error, {:missing_context, key}}
      other -> {:error, {:invalid_context, {key, other}}}
    end
  end

  defp resolve_peer_pid(peer_id) when is_binary(peer_id) do
    case Moto.whereis(peer_id) do
      nil -> {:error, {:subagent_peer_not_found, peer_id}}
      pid -> {:ok, pid}
    end
  end

  defp verify_peer_runtime(agent_module, pid) do
    expected_runtime = agent_module.runtime_module()

    case Jido.AgentServer.state(pid) do
      {:ok, %{agent_module: ^expected_runtime}} ->
        :ok

      {:ok, %{agent_module: other}} ->
        {:error, {:subagent_peer_mismatch, expected_runtime, other}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_task(%{task: task}) when is_binary(task) and task != "", do: {:ok, task}
  defp fetch_task(%{"task" => task}) when is_binary(task) and task != "", do: {:ok, task}
  defp fetch_task(_params), do: {:error, {:invalid_subagent_task, :expected_non_empty_string}}

  defp ensure_depth_allowed(context) do
    if current_depth(context) >= 1 do
      {:error, {:subagent_recursion_limit, 1}}
    else
      :ok
    end
  end

  defp forwarded_context(context) do
    context
    |> Moto.Context.sanitize_for_subagent()
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
      ensure_meta_table()
      :ets.insert(@meta_table, {{parent_server, request_id}, metadata})
    end

    :ok
  end

  defp maybe_record_metadata(_context, _metadata), do: :ok

  defp drain_request_meta(server, request_id) when is_pid(server) and is_binary(request_id) do
    ensure_meta_table()

    @meta_table
    |> :ets.take({server, request_id})
    |> Enum.map(fn {{^server, ^request_id}, metadata} -> metadata end)
  end

  defp drain_request_meta(_server, _request_id), do: []

  defp lookup_request_meta(server, request_id) when is_pid(server) and is_binary(request_id) do
    ensure_meta_table()

    @meta_table
    |> :ets.lookup({server, request_id})
    |> Enum.map(fn {{^server, ^request_id}, metadata} -> metadata end)
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
         outcome
       ) do
    %{
      name: subagent.name,
      agent: subagent.agent,
      mode: mode,
      task_preview: task_preview(task),
      child_id: child_id,
      child_request_id: child_request_id,
      duration_ms: System.monotonic_time(:millisecond) - started_at,
      outcome: outcome,
      child_result_meta: child_result_meta
    }
  end

  defp error_metadata(subagent, reason) do
    %{
      name: subagent.name,
      agent: subagent.agent,
      mode: target_mode(subagent.target),
      task_preview: nil,
      child_id: nil,
      child_request_id: nil,
      duration_ms: 0,
      outcome: {:error, reason},
      child_result_meta: %{}
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

  defp ensure_meta_table do
    case :ets.whereis(@meta_table) do
      :undefined ->
        :ets.new(@meta_table, [:bag, :public, :named_table, read_concurrency: true])

      _ ->
        @meta_table
    end
  rescue
    ArgumentError -> @meta_table
  end
end
