defmodule Jidoka.Examples.MeetingFollowup.Tools.LoadMeetingNotes do
  @moduledoc false

  use Jidoka.Tool,
    description: "Loads fixture-backed meeting notes.",
    schema: Zoi.object(%{meeting_id: Zoi.string()})

  @meetings %{
    "CS-42" => %{
      meeting_id: "CS-42",
      title: "Northwind onboarding check-in",
      attendees: ["Maya", "Luis", "Priya"],
      notes:
        "Decision: launch pilot on May 6. Maya owns the sandbox invite by Friday. Luis will send SSO docs. Risk: billing export is still blocked."
    }
  }

  @impl true
  def run(%{meeting_id: meeting_id}, _context) do
    case Map.fetch(@meetings, meeting_id) do
      {:ok, meeting} -> {:ok, meeting}
      :error -> {:error, {:unknown_meeting, meeting_id}}
    end
  end
end
