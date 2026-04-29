defmodule Jidoka.Examples.LeadQualification.Agents.LeadAgent do
  @moduledoc false

  use Jidoka.Agent

  @context_schema Zoi.object(%{
                    territory: Zoi.string() |> Zoi.default("na"),
                    source: Zoi.string() |> Zoi.default("inbound")
                  })

  @output_schema Zoi.object(%{
                   company: Zoi.string(),
                   segment: Zoi.enum([:startup, :mid_market, :enterprise]),
                   fit_score: Zoi.integer(),
                   intent: Zoi.enum([:low, :medium, :high]),
                   recommended_action: Zoi.enum([:nurture, :sales_follow_up, :solutions_engineer]),
                   summary: Zoi.string()
                 })

  agent do
    id :lead_qualification_agent
    schema @context_schema

    output do
      schema @output_schema
      retries(1)
      on_validation_error(:repair)
    end
  end

  defaults do
    model :fast

    instructions """
    You qualify inbound leads for a B2B SaaS sales team.
    Use enrichment and scoring tools before producing a CRM-ready structured result.
    """
  end

  capabilities do
    tool Jidoka.Examples.LeadQualification.Tools.EnrichCompany
    tool Jidoka.Examples.LeadQualification.Tools.ScoreLead
  end
end
