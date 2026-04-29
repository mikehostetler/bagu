defmodule Jidoka.Agent.Definition.MemoryConfig do
  @moduledoc false

  @spec resolve!(module(), term()) :: Jidoka.Memory.config() | nil
  def resolve!(owner_module, context_schema) do
    memory_entities =
      owner_module
      |> Spark.Dsl.Extension.get_entities([:lifecycle, :memory])
      |> Enum.filter(&memory_entity?/1)

    memory_section_anno =
      owner_module
      |> Module.get_attribute(:spark_dsl_config)
      |> case do
        %{} = dsl -> Spark.Dsl.Extension.get_section_anno(dsl, [:lifecycle, :memory])
        _ -> nil
      end

    cond do
      memory_entities != [] ->
        owner_module
        |> resolve_memory!(memory_entities)
        |> validate_namespace_context!(owner_module, context_schema)

      not is_nil(memory_section_anno) ->
        Jidoka.Memory.default_config()
        |> validate_namespace_context!(owner_module, context_schema)

      true ->
        nil
    end
  end

  defp resolve_memory!(owner_module, entries) when is_list(entries) do
    case Jidoka.Memory.normalize_dsl(entries) do
      {:ok, normalized} ->
        normalized

      {:error, message} ->
        raise Jidoka.Agent.Dsl.Error.exception(
                message: message,
                path: [:lifecycle, :memory],
                hint: "Declare each memory setting once and keep shared namespace settings consistent.",
                module: owner_module
              )
    end
  end

  defp validate_namespace_context!(nil, _owner_module, _context_schema), do: nil

  defp validate_namespace_context!(%{namespace: {:context, key}} = memory, owner_module, context_schema)
       when not is_nil(context_schema) do
    if Jidoka.Context.schema_has_key?(context_schema, key) do
      memory
    else
      raise Jidoka.Agent.Dsl.Error.exception(
              message: "memory context namespace key is not declared by `agent.schema`.",
              path: [:lifecycle, :memory, :namespace],
              value: {:context, key},
              hint: "Add #{inspect(key)} to the Zoi schema or use `namespace :per_agent`/`:shared`.",
              module: owner_module
            )
    end
  end

  defp validate_namespace_context!(memory, _owner_module, _context_schema), do: memory

  defp memory_entity?(entity) do
    match?(%Jidoka.Agent.Dsl.MemoryMode{}, entity) or
      match?(%Jidoka.Agent.Dsl.MemoryNamespace{}, entity) or
      match?(%Jidoka.Agent.Dsl.MemorySharedNamespace{}, entity) or
      match?(%Jidoka.Agent.Dsl.MemoryCapture{}, entity) or
      match?(%Jidoka.Agent.Dsl.MemoryInject{}, entity) or
      match?(%Jidoka.Agent.Dsl.MemoryRetrieve{}, entity)
  end
end
