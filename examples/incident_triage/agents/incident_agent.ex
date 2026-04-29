defmodule Jidoka.Examples.IncidentTriage.Agents.IncidentAgent do
  @moduledoc false

  use Jidoka.Agent

  @output_schema Zoi.object(%{
                   severity: Zoi.enum([:sev1, :sev2, :sev3]),
                   affected_service: Zoi.string(),
                   likely_causes: Zoi.list(Zoi.string()),
                   recommended_actions: Zoi.list(Zoi.string()),
                   escalate: Zoi.boolean()
                 })

  agent do
    id :incident_triage_agent

    output do
      schema @output_schema
      retries(1)
      on_validation_error(:repair)
    end
  end

  defaults do
    model :fast

    instructions """
    You triage production alerts.
    Use the deterministic incident workflow before returning a response plan.
    """
  end

  capabilities do
    workflow(Jidoka.Examples.IncidentTriage.Workflows.InvestigateIncident,
      as: :investigate_incident,
      result: :structured
    )
  end
end
