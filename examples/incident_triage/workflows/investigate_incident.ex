defmodule Jidoka.Examples.IncidentTriage.Workflows.InvestigateIncident do
  @moduledoc false

  use Jidoka.Workflow

  workflow do
    id :incident_investigation
    description "Classifies an alert, loads service context, and builds a response plan."
    input Zoi.object(%{alert_id: Zoi.string()})
  end

  steps do
    tool :classify, Jidoka.Examples.IncidentTriage.Tools.ClassifyAlert, input: %{alert_id: input(:alert_id)}

    tool :snapshot, Jidoka.Examples.IncidentTriage.Tools.LoadServiceSnapshot, input: from(:classify)
  end

  output from(:snapshot)
end
