defmodule Jidoka.Examples.ResearchBrief.Guardrails.RequireSources do
  @moduledoc false

  use Jidoka.Guardrail, name: "require_sources"

  @impl true
  def call(%Jidoka.Guardrails.Output{outcome: {:ok, result}}) when is_map(result) do
    sources = Map.get(result, :sources, Map.get(result, "sources", []))

    if sources == [] do
      {:error, :missing_sources}
    else
      :ok
    end
  end

  def call(%Jidoka.Guardrails.Output{}), do: :ok
end
