defmodule Jidoka.Examples.LeadQualification.Tools.ScoreLead do
  @moduledoc false

  use Jidoka.Tool,
    description: "Scores a lead based on company size and buying intent.",
    schema:
      Zoi.object(%{
        employees: Zoi.integer(),
        recent_signal: Zoi.string()
      })

  @impl true
  def run(%{employees: employees, recent_signal: signal}, _context) do
    intent = if String.contains?(String.downcase(signal), "pricing"), do: :high, else: :medium
    score = employees_score(employees) + intent_score(intent)

    {:ok,
     %{
       fit_score: min(score, 100),
       segment: segment(employees),
       intent: intent,
       recommended_action: action(score, intent)
     }}
  end

  defp employees_score(count) when count >= 1000, do: 55
  defp employees_score(count) when count >= 100, do: 35
  defp employees_score(_count), do: 20

  defp intent_score(:high), do: 40
  defp intent_score(:medium), do: 25

  defp segment(count) when count >= 1000, do: :enterprise
  defp segment(count) when count >= 100, do: :mid_market
  defp segment(_count), do: :startup

  defp action(score, :high) when score >= 85, do: :solutions_engineer
  defp action(score, _intent) when score >= 60, do: :sales_follow_up
  defp action(_score, _intent), do: :nurture
end
