defmodule Jidoka.Examples.ResearchBrief.Tools.RankSources do
  @moduledoc false

  use Jidoka.Tool,
    description: "Ranks fixture-backed sources by relevance.",
    schema: Zoi.object(%{sources: Zoi.list(Zoi.map())})

  @impl true
  def run(%{sources: sources}, _context) do
    ranked =
      sources
      |> Enum.with_index(1)
      |> Enum.map(fn {source, rank} -> Map.put(source, :rank, rank) end)

    {:ok, %{ranked_sources: ranked}}
  end
end
