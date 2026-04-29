defmodule Jidoka.Examples.FeedbackSynthesizer.Tools.GroupThemes do
  @moduledoc false

  use Jidoka.Tool,
    description: "Groups product feedback comments into deterministic themes.",
    schema: Zoi.object(%{comments: Zoi.list(Zoi.string())})

  @impl true
  def run(%{comments: comments}, _context) do
    themes = [
      %{name: "debuggability", count: 2, representative_comment: Enum.at(comments, 0)},
      %{name: "structured output operations", count: 1, representative_comment: Enum.at(comments, 1)},
      %{name: "examples", count: 1, representative_comment: Enum.at(comments, 3)}
    ]

    {:ok, %{themes: themes, sentiment: :mixed}}
  end
end
