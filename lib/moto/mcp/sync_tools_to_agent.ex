defmodule Moto.MCP.SyncToolsToAgent do
  @moduledoc false

  alias Jido.MCP.Config
  alias Jido.MCP.JidoAI.{ProxyGenerator, ProxyRegistry}

  @max_tools 200
  @max_schema_depth 8
  @max_schema_properties 200
  @schema_metadata_keys ~w($schema $id format)

  @spec run(map(), map()) :: {:ok, map()} | {:error, term()}
  def run(params, _context) when is_map(params) do
    with :ok <- ensure_jido_ai_loaded(),
         {:ok, endpoint_id} <- Config.resolve_endpoint_id(params[:endpoint_id]),
         {:ok, response} <- Jido.MCP.list_tools(endpoint_id),
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

      {registered, failed} = register_modules(params[:agent_server], modules)
      skipped_failures = Enum.map(skipped, &{&1.tool_name, &1.reason})
      failed = skipped_failures ++ failed

      ProxyRegistry.put(params[:agent_server], endpoint_id, registered)

      {:ok,
       %{
         endpoint_id: endpoint_id,
         discovered_count: length(tools),
         registered_count: length(registered),
         failed_count: length(failed),
         failed: failed,
         warnings: warnings,
         skipped_count: length(skipped),
         registered_tools: Enum.map(registered, & &1.name())
       }}
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

  defp register_modules(agent_server, modules) do
    jido_ai = Module.concat([Jido, AI])

    modules
    |> Enum.reduce({[], []}, fn module, {ok, err} ->
      case apply(jido_ai, :register_tool, [agent_server, module]) do
        {:ok, _agent} -> {[module | ok], err}
        {:error, reason} -> {ok, [{module, reason} | err]}
      end
    end)
    |> then(fn {ok, err} -> {Enum.reverse(ok), Enum.reverse(err)} end)
  end

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
