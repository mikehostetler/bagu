defmodule Jidoka.Subagent.Runtime.Result do
  @moduledoc false

  @spec visible_result(map(), term(), map()) :: map()
  def visible_result(%{result: :structured}, result, metadata) do
    %{result: result, subagent: visible_metadata(metadata)}
  end

  def visible_result(%{}, result, _metadata), do: %{result: result}

  @spec normalize_error(map(), term(), map(), map()) :: term()
  def normalize_error(subagent, reason, context, metadata) do
    Jidoka.Error.Normalize.subagent_error(reason,
      agent_id: subagent.name,
      target: subagent.target,
      request_id: Map.get(context, Jidoka.Subagent.Context.request_id_key()) || Map.get(metadata, :child_request_id),
      cause: reason
    )
  end

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
  defp visible_outcome({:error, reason}), do: {:error, Jidoka.Error.format(reason)}
  defp visible_outcome(other), do: other
end
