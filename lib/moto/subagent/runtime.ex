defmodule Moto.Subagent.Runtime do
  @moduledoc false

  alias Jido.AI.Request

  @request_meta_key :moto_subagents

  @spec on_before_cmd(Jido.Agent.t(), term()) :: {:ok, Jido.Agent.t(), term()}
  def on_before_cmd(agent, {:ai_react_start, %{request_id: request_id} = params})
      when is_binary(request_id) do
    context = Map.get(params, :tool_context, %{}) || %{}

    context =
      context
      |> Map.put(Moto.Subagent.request_id_key(), request_id)
      |> Map.put(Moto.Subagent.server_key(), self())
      |> Map.put_new(Moto.Subagent.depth_key(), current_depth(context))

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

  @spec run_subagent_tool(Moto.Subagent.t(), map(), map()) :: {:ok, map()} | {:error, term()}
  def run_subagent_tool(%Moto.Subagent{} = subagent, params, context)
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

  @spec run_subagent(Moto.Subagent.t(), map(), map()) :: {:ok, String.t()} | {:error, term()}
  def run_subagent(%Moto.Subagent{} = subagent, params, context)
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

  @spec request_calls(pid() | String.t() | Jido.Agent.t(), String.t()) :: [map()]
  def request_calls(server_or_agent, request_id) when is_binary(request_id) do
    stored_calls = stored_request_calls(server_or_agent, request_id)
    pending_calls = pending_request_calls(server_or_agent, request_id)

    (stored_calls ++ pending_calls)
    |> Enum.sort_by(&Map.get(&1, :sequence, 0))
    |> Enum.uniq_by(&request_call_identity/1)
  end

  def request_calls(_server_or_agent, _request_id), do: []

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

  defp visible_result(%Moto.Subagent{result: :structured}, result, metadata) do
    %{result: result, subagent: visible_metadata(metadata)}
  end

  defp visible_result(%Moto.Subagent{}, result, _metadata), do: %{result: result}

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

  defp generated_child_id(%Moto.Subagent{name: name}) do
    unique = System.unique_integer([:positive])
    "moto-subagent-#{name}-#{unique}"
  end

  defp execute_subagent(%Moto.Subagent{} = subagent, params, context) do
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
         %Moto.Subagent{target: :ephemeral} = subagent,
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
         %Moto.Subagent{target: {:peer, peer_ref}} = subagent,
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
    |> Map.put(Moto.Subagent.depth_key(), current_depth(context) + 1)
  end

  defp current_depth(context) when is_map(context) do
    case Map.get(context, Moto.Subagent.depth_key(), 0) do
      depth when is_integer(depth) and depth >= 0 -> depth
      _ -> 0
    end
  end

  defp maybe_record_metadata(context, metadata) when is_map(context) and is_map(metadata) do
    parent_server = Map.get(context, Moto.Subagent.server_key())
    request_id = Map.get(context, Moto.Subagent.request_id_key())

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
    |> Map.drop([
      Moto.Subagent.request_id_key(),
      Moto.Subagent.server_key(),
      Moto.Subagent.depth_key()
    ])
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

  defp key_to_string(key) when is_atom(key), do: Atom.to_string(key)
  defp key_to_string(key) when is_binary(key), do: key
  defp key_to_string(key), do: inspect(key)
end
