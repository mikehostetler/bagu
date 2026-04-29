defmodule Jidoka.Subagent.Runtime.Calls do
  @moduledoc false

  @request_meta_key :jidoka_subagents

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

  @spec record_metadata(map(), map()) :: :ok
  def record_metadata(context, metadata) when is_map(context) and is_map(metadata) do
    parent_server = Map.get(context, Jidoka.Subagent.Context.server_key())
    request_id = Map.get(context, Jidoka.Subagent.Context.request_id_key())

    if is_pid(parent_server) and is_binary(request_id) do
      Jidoka.Subagent.Metadata.insert(parent_server, request_id, metadata)
    end

    :ok
  end

  def record_metadata(_context, _metadata), do: :ok

  @spec drain_request_meta(pid(), String.t()) :: [map()]
  def drain_request_meta(server, request_id) when is_pid(server) and is_binary(request_id) do
    Jidoka.Subagent.Metadata.drain(server, request_id)
  end

  def drain_request_meta(_server, _request_id), do: []

  @spec put_request_meta(Jido.Agent.t(), String.t(), %{calls: [map()]}) :: Jido.Agent.t()
  def put_request_meta(agent, request_id, %{calls: calls}) do
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

  defp lookup_request_meta(server, request_id) when is_pid(server) and is_binary(request_id) do
    Jidoka.Subagent.Metadata.lookup(server, request_id)
  end

  defp lookup_request_meta(_server, _request_id), do: []

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
    case Jidoka.Runtime.whereis(server_id) do
      nil -> []
      pid -> lookup_request_meta(pid, request_id)
    end
  end

  defp pending_request_calls(_server_or_agent, _request_id), do: []

  defp request_call_identity(%{sequence: sequence}) when is_integer(sequence),
    do: {:sequence, sequence}

  defp request_call_identity(call) when is_map(call) do
    {:fallback, Map.get(call, :name), Map.get(call, :child_request_id), Map.get(call, :child_id)}
  end
end
