defmodule Jidoka.Examples.DataAnalyst.Tools.ComparePeriods do
  @moduledoc false

  use Jidoka.Tool,
    description: "Compares two numeric metric values and returns the percentage change.",
    schema:
      Zoi.object(%{
        current: Zoi.float(),
        previous: Zoi.float()
      })

  @impl true
  def run(%{current: current, previous: previous}, _context) when previous != 0 do
    change = (current - previous) / previous * 100.0
    {:ok, %{change_percent: Float.round(change, 2), direction: direction(change)}}
  end

  def run(%{previous: 0}, _context), do: {:error, :cannot_compare_against_zero}

  defp direction(change) when change > 0, do: :up
  defp direction(change) when change < 0, do: :down
  defp direction(_change), do: :flat
end
