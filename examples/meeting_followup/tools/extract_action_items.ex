defmodule Jidoka.Examples.MeetingFollowup.Tools.ExtractActionItems do
  @moduledoc false

  use Jidoka.Tool,
    description: "Extracts action items from fixture-backed meeting notes.",
    schema: Zoi.object(%{notes: Zoi.string()})

  @impl true
  def run(%{notes: notes}, _context) do
    items =
      [
        %{owner: "Maya", task: "Send sandbox invite", due: "Friday"},
        %{owner: "Luis", task: "Send SSO documentation", due: "Friday"}
      ]

    {:ok, %{action_items: items, count: length(items), source_preview: String.slice(notes, 0, 80)}}
  end
end
