defmodule Jidoka.MCP.Sync do
  @moduledoc false

  alias Jido.Agent
  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.AI.ToolAdapter
  alias Jido.MCP.ClientPool
  alias Jido.MCP.JidoAI.{ProxyGenerator, ProxyRegistry}

  @max_tools 200
  @max_schema_depth 8
  @max_schema_properties 200
  @list_tools_attempts 10
  @list_tools_retry_ms 250
  @schema_metadata_keys ~w($schema $id format)

  @spec run(map(), map()) :: {:ok, map()} | {:error, term()}
  def run(params, _context) when is_map(params) do
    with :ok <- ensure_jido_ai_loaded(),
         {:ok, endpoint_id} <- ClientPool.resolve_endpoint_id(params[:endpoint_id]),
         {:ok, response} <- list_tools_with_retry(endpoint_id),
         tools when is_list(tools) <- get_in(response, [:data, "tools"]) || [],
         :ok <- ensure_tool_limit(tools),
         {:ok, modules, warnings, skipped} <-
           ProxyGenerator.build_modules(endpoint_id, sanitize_tools(tools),
             prefix: params[:prefix],
             max_schema_depth: @max_schema_depth,
             max_schema_properties: @max_schema_properties
           ) do
      if params[:replace_existing] != false do
        _ = unregister_previous(params[:agent_server], endpoint_id)
      end

      {registered, failed, agent} =
        register_modules(params[:agent_server], modules, params[:agent])

      skipped_failures = Enum.map(skipped, &{&1.tool_name, &1.reason})
      failed = skipped_failures ++ failed

      ProxyRegistry.put(params[:agent_server], endpoint_id, registered)

      result =
        %{
          endpoint_id: endpoint_id,
          discovered_count: length(tools),
          registered_count: length(registered),
          failed_count: length(failed),
          failed: failed,
          warnings: warnings,
          skipped_count: length(skipped),
          registered_tools: Enum.map(registered, & &1.name())
        }
        |> maybe_put_agent(agent)

      {:ok, result}
    end
  end

  defp ensure_jido_ai_loaded do
    module = Module.concat([Jido, AI])

    if Code.ensure_loaded?(module) do
      :ok
    else
      {:error, :jido_ai_not_available}
    end
  end

  defp ensure_tool_limit(tools) when length(tools) > @max_tools do
    {:error, {:tool_limit_exceeded, %{max_tools: @max_tools, discovered: length(tools)}}}
  end

  defp ensure_tool_limit(_tools), do: :ok

  defp list_tools_with_retry(endpoint_id, attempts \\ @list_tools_attempts)

  defp list_tools_with_retry(endpoint_id, attempts) do
    case Jido.MCP.list_tools(endpoint_id) do
      {:ok, _response} = ok ->
        ok

      {:error, reason} = error when attempts > 1 ->
        if capabilities_pending?(reason) do
          Process.sleep(@list_tools_retry_ms)
          list_tools_with_retry(endpoint_id, attempts - 1)
        else
          error
        end

      error ->
        error
    end
  end

  defp capabilities_pending?(reason) do
    reason
    |> inspect()
    |> String.contains?("Server capabilities not set")
  end

  defp register_modules(_agent_server, modules, %Agent{} = agent) do
    {registered, failed} =
      Enum.reduce(modules, {[], []}, fn module, {ok, err} ->
        case validate_proxy_module(module) do
          :ok -> {[module | ok], err}
          {:error, reason} -> {ok, [{module, reason} | err]}
        end
      end)
      |> then(fn {ok, err} -> {Enum.reverse(ok), Enum.reverse(err)} end)

    {registered, failed, register_modules_directly(agent, registered)}
  end

  defp register_modules(agent_server, modules, _agent) do
    jido_ai = Module.concat([Jido, AI])

    modules
    |> Enum.reduce({[], []}, fn module, {ok, err} ->
      case apply(jido_ai, :register_tool, [agent_server, module]) do
        {:ok, _agent} -> {[module | ok], err}
        {:error, reason} -> {ok, [{module, reason} | err]}
      end
    end)
    |> then(fn {ok, err} -> {Enum.reverse(ok), Enum.reverse(err), nil} end)
  end

  defp validate_proxy_module(module) do
    cond do
      not Code.ensure_loaded?(module) ->
        {:error, {:not_loaded, module}}

      not function_exported?(module, :name, 0) ->
        {:error, :not_a_tool}

      not function_exported?(module, :schema, 0) ->
        {:error, :not_a_tool}

      not function_exported?(module, :run, 2) ->
        {:error, :not_a_tool}

      true ->
        :ok
    end
  end

  defp register_modules_directly(%Agent{} = agent, []), do: agent

  defp register_modules_directly(%Agent{} = agent, modules) do
    StratState.update(agent, fn state ->
      config = Map.get(state, :config, %{})
      tools = (modules ++ Map.get(config, :tools, [])) |> Enum.uniq()

      actions_by_name =
        Enum.reduce(modules, Map.get(config, :actions_by_name, %{}), fn module, acc ->
          Map.put(acc, module.name(), module)
        end)

      reqllm_tools = ToolAdapter.from_actions(tools)

      config =
        config
        |> Map.put(:tools, tools)
        |> Map.put(:actions_by_name, actions_by_name)
        |> Map.put(:reqllm_tools, reqllm_tools)

      Map.put(state, :config, config)
    end)
  end

  defp maybe_put_agent(result, nil), do: result
  defp maybe_put_agent(result, %Agent{} = agent), do: Map.put(result, :agent, agent)

  defp unregister_previous(agent_server, endpoint_id) do
    jido_ai = Module.concat([Jido, AI])

    agent_server
    |> ProxyRegistry.get(endpoint_id)
    |> Enum.each(fn module ->
      _ = apply(jido_ai, :unregister_tool, [agent_server, module.name()])
    end)

    _ = ProxyRegistry.delete(agent_server, endpoint_id)
    :ok
  end

  defp sanitize_tools(tools), do: Enum.map(tools, &sanitize_tool/1)

  defp sanitize_tool(%{} = tool) do
    Map.update(tool, "inputSchema", nil, &sanitize_schema/1)
  end

  defp sanitize_tool(tool), do: tool

  defp sanitize_schema(%{} = schema) do
    Enum.reduce(schema, %{}, fn {key, value}, acc ->
      key = to_string(key)

      cond do
        key in @schema_metadata_keys ->
          acc

        key == "properties" and is_map(value) ->
          Map.put(acc, key, sanitize_properties(value))

        true ->
          Map.put(acc, key, sanitize_schema(value))
      end
    end)
  end

  defp sanitize_schema(values) when is_list(values), do: Enum.map(values, &sanitize_schema/1)
  defp sanitize_schema(value), do: value

  defp sanitize_properties(properties) do
    Map.new(properties, fn {property_name, property_schema} ->
      {to_string(property_name), sanitize_schema(property_schema)}
    end)
  end
end
