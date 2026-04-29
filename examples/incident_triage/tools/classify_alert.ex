defmodule Jidoka.Examples.IncidentTriage.Tools.ClassifyAlert do
  @moduledoc false

  use Jidoka.Tool,
    description: "Classifies a fixture-backed alert.",
    schema: Zoi.object(%{alert_id: Zoi.string()})

  @impl true
  def run(%{alert_id: "ALERT-9"}, _context) do
    {:ok, %{alert_id: "ALERT-9", service: "checkout-api", severity: :sev2, signal: "error-rate"}}
  end

  def run(%{alert_id: alert_id}, _context), do: {:error, {:unknown_alert, alert_id}}
end
