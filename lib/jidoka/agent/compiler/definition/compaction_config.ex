defmodule Jidoka.Agent.Definition.CompactionConfig do
  @moduledoc false

  @spec resolve!(module()) :: Jidoka.Compaction.config() | nil
  def resolve!(owner_module) do
    compaction_entities =
      owner_module
      |> Spark.Dsl.Extension.get_entities([:lifecycle, :compaction])
      |> Enum.filter(&compaction_entity?/1)

    compaction_section_anno =
      owner_module
      |> Module.get_attribute(:spark_dsl_config)
      |> case do
        %{} = dsl -> Spark.Dsl.Extension.get_section_anno(dsl, [:lifecycle, :compaction])
        _ -> nil
      end

    cond do
      compaction_entities != [] ->
        resolve_compaction!(owner_module, compaction_entities)

      not is_nil(compaction_section_anno) ->
        Jidoka.Compaction.default_config()

      true ->
        nil
    end
  end

  defp resolve_compaction!(owner_module, entries) when is_list(entries) do
    case Jidoka.Compaction.normalize_dsl(entries, owner_module) do
      {:ok, normalized} ->
        normalized

      {:error, message} ->
        raise Jidoka.Agent.Dsl.Error.exception(
                message: message,
                path: [:lifecycle, :compaction],
                hint: "Declare each compaction setting once and keep keep_last lower than max_messages.",
                module: owner_module
              )
    end
  end

  defp compaction_entity?(entity) do
    match?(%Jidoka.Agent.Dsl.CompactionMode{}, entity) or
      match?(%Jidoka.Agent.Dsl.CompactionStrategy{}, entity) or
      match?(%Jidoka.Agent.Dsl.CompactionMaxMessages{}, entity) or
      match?(%Jidoka.Agent.Dsl.CompactionKeepLast{}, entity) or
      match?(%Jidoka.Agent.Dsl.CompactionMaxSummaryChars{}, entity) or
      match?(%Jidoka.Agent.Dsl.CompactionPrompt{}, entity)
  end
end
