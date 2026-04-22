defmodule Moto.MCP do
  @moduledoc false

  @state_key :__moto_mcp__

  @type endpoint_ref :: atom() | String.t()
  @type config :: [%{endpoint: endpoint_ref(), prefix: String.t() | nil}]

  @spec normalize_dsl([struct()]) :: {:ok, config()} | {:error, String.t()}
  def normalize_dsl(entries) when is_list(entries) do
    entries
    |> Enum.reduce_while({:ok, []}, fn %Moto.Agent.Dsl.MCPTools{
                                         endpoint: endpoint,
                                         prefix: prefix
                                       },
                                       {:ok, acc} ->
      with {:ok, normalized} <- normalize_entry(%{endpoint: endpoint, prefix: prefix}),
           :ok <- ensure_unique_endpoint(normalized, acc) do
        {:cont, {:ok, acc ++ [normalized]}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @spec normalize_imported([map()]) :: {:ok, config()} | {:error, String.t()}
  def normalize_imported(entries) when is_list(entries) do
    entries
    |> Enum.reduce_while({:ok, []}, fn entry, {:ok, acc} ->
      with true <- is_map(entry) or {:error, "mcp_tools entries must be maps"},
           {:ok, normalized} <- normalize_entry(entry),
           :ok <- ensure_unique_endpoint(normalized, acc) do
        {:cont, {:ok, acc ++ [normalized]}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  def normalize_imported(other),
    do: {:error, "mcp_tools must be a list of maps, got: #{inspect(other)}"}

  @spec validate_dsl_entry(struct()) :: :ok | {:error, String.t()}
  def validate_dsl_entry(%Moto.Agent.Dsl.MCPTools{endpoint: endpoint, prefix: prefix}) do
    with {:ok, _normalized} <- normalize_entry(%{endpoint: endpoint, prefix: prefix}) do
      :ok
    end
  end

  @spec on_before_cmd(Jido.Agent.t(), term(), config()) :: {:ok, Jido.Agent.t(), term()}
  def on_before_cmd(agent, action, []), do: {:ok, agent, action}

  def on_before_cmd(agent, {:ai_react_start, _params} = action, config) when is_list(config) do
    context =
      case action do
        {:ai_react_start, %{tool_context: tool_context}} when is_map(tool_context) -> tool_context
        _ -> %{}
      end

    synced = agent.state |> Map.get(@state_key, %{}) |> Map.get(:synced, %{})

    {agent, synced, errors} =
      Enum.reduce(config, {agent, synced, []}, fn entry, {agent_acc, synced_acc, errors_acc} ->
        key = sync_key(entry)

        if Map.get(synced_acc, key, false) do
          {agent_acc, synced_acc, errors_acc}
        else
          case sync_endpoint(entry, agent_acc) do
            {:ok, updated_agent} ->
              {updated_agent, Map.put(synced_acc, key, true), errors_acc}

            {:error, reason} ->
              {agent_acc, synced_acc, [format_error(entry, reason) | errors_acc]}
          end
        end
      end)

    :ok =
      Moto.Debug.record_runtime_meta(
        context,
        %{
          mcp_tools: Enum.map(config, &format_entry/1),
          mcp_errors: Enum.reverse(errors)
        }
        |> drop_empty_errors()
      )

    {:ok, put_mcp_state(agent, synced, errors), action}
  end

  def on_before_cmd(agent, action, _config), do: {:ok, agent, action}

  defp normalize_entry(entry) when is_map(entry) do
    endpoint = Map.get(entry, :endpoint, Map.get(entry, "endpoint"))
    prefix = Map.get(entry, :prefix, Map.get(entry, "prefix"))

    with {:ok, normalized_endpoint} <- normalize_endpoint(endpoint),
         {:ok, normalized_prefix} <- normalize_prefix(prefix) do
      {:ok, %{endpoint: normalized_endpoint, prefix: normalized_prefix}}
    end
  end

  defp normalize_endpoint(endpoint) when is_atom(endpoint), do: {:ok, endpoint}

  defp normalize_endpoint(endpoint) when is_binary(endpoint) do
    trimmed = String.trim(endpoint)

    if trimmed == "" do
      {:error, "mcp endpoint must not be empty"}
    else
      {:ok, trimmed}
    end
  end

  defp normalize_endpoint(other),
    do: {:error, "mcp endpoint must be an atom or string, got: #{inspect(other)}"}

  defp normalize_prefix(nil), do: {:ok, nil}

  defp normalize_prefix(prefix) when is_binary(prefix) do
    trimmed = String.trim(prefix)

    if trimmed == "" do
      {:error, "mcp prefix must not be empty when provided"}
    else
      {:ok, trimmed}
    end
  end

  defp normalize_prefix(other),
    do: {:error, "mcp prefix must be a string when provided, got: #{inspect(other)}"}

  defp ensure_unique_endpoint(entry, acc) do
    if Enum.any?(acc, fn existing -> existing.endpoint == entry.endpoint end) do
      {:error, "mcp endpoint #{inspect(entry.endpoint)} is defined more than once"}
    else
      :ok
    end
  end

  defp put_mcp_state(agent, synced, errors) do
    state =
      agent.state
      |> Map.get(@state_key, %{})
      |> Map.put(:synced, synced)
      |> Map.put(:last_errors, Enum.reverse(errors))

    %{agent | state: Map.put(agent.state, @state_key, state)}
  end

  defp sync_endpoint(entry, agent) do
    sync_module =
      Application.get_env(:moto, :mcp_sync_module, Moto.MCP.SyncToolsToAgent)

    params =
      %{
        endpoint_id: entry.endpoint,
        agent_server: self(),
        agent: agent,
        replace_existing: false
      }
      |> maybe_put_prefix(entry.prefix)

    case sync_module.run(params, %{}) do
      {:ok, %{agent: %Jido.Agent{} = updated_agent}} -> {:ok, updated_agent}
      {:ok, _result} -> {:ok, agent}
      {:error, reason} -> {:error, reason}
    end
  rescue
    error ->
      {:error, Exception.message(error)}
  end

  defp maybe_put_prefix(params, nil), do: params
  defp maybe_put_prefix(params, prefix), do: Map.put(params, :prefix, prefix)

  defp sync_key(%{endpoint: endpoint, prefix: prefix}), do: {endpoint, prefix}

  defp format_entry(%{endpoint: endpoint, prefix: nil}), do: to_string(endpoint)
  defp format_entry(%{endpoint: endpoint, prefix: prefix}), do: "#{endpoint}:#{prefix}"

  defp format_error(entry, reason) do
    %{
      endpoint: entry.endpoint,
      prefix: entry.prefix,
      reason: {:mcp_sync_failed, entry.endpoint, reason}
    }
  end

  defp drop_empty_errors(%{mcp_errors: []} = meta), do: Map.delete(meta, :mcp_errors)
  defp drop_empty_errors(meta), do: meta
end
