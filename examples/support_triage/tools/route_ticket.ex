defmodule Jidoka.Examples.SupportTriage.Tools.RouteTicket do
  @moduledoc false

  use Jidoka.Tool,
    description: "Maps a support triage category and priority to an operational queue.",
    schema:
      Zoi.object(%{
        category: Zoi.enum([:billing, :technical, :account]),
        priority: Zoi.enum([:low, :normal, :high, :urgent])
      })

  @impl true
  def run(%{category: category, priority: priority}, _context) do
    {:ok,
     %{
       route: route(category),
       sla_minutes: sla_minutes(priority),
       escalation_required: priority in [:urgent, :high]
     }}
  end

  defp route(:billing), do: :billing_ops
  defp route(:technical), do: :technical_support
  defp route(:account), do: :account_success

  defp sla_minutes(:urgent), do: 15
  defp sla_minutes(:high), do: 60
  defp sla_minutes(:normal), do: 240
  defp sla_minutes(:low), do: 1440
end
