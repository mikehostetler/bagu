defmodule Jidoka.Examples.IncidentTriage.Tools.LoadServiceSnapshot do
  @moduledoc false

  use Jidoka.Tool,
    description: "Loads service context and builds a response plan for an incident.",
    schema:
      Zoi.object(%{
        alert_id: Zoi.string(),
        service: Zoi.string(),
        severity: Zoi.enum([:sev1, :sev2, :sev3]),
        signal: Zoi.string()
      })

  @impl true
  def run(%{service: "checkout-api", severity: severity}, _context) do
    {:ok,
     %{
       severity: severity,
       affected_service: "checkout-api",
       error_rate: 8.7,
       recent_deploy: "checkout-api@2026.04.29.2",
       likely_causes: ["Recent deploy checkout-api@2026.04.29.2", "payment adapter timeout spike"],
       recommended_actions: ["Page checkout owner", "Inspect payment adapter timeout logs", "Prepare rollback"],
       escalate: severity in [:sev1, :sev2]
     }}
  end

  def run(%{service: service}, _context), do: {:error, {:unknown_service, service}}
end
