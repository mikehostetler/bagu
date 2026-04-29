defmodule Jidoka.Examples.DataAnalyst.Agents.AnalystAgent do
  @moduledoc false

  use Jidoka.Agent

  @context_schema Zoi.object(%{
                    workspace: Zoi.string() |> Zoi.default("demo-analytics"),
                    audience: Zoi.string() |> Zoi.default("operator")
                  })

  @output_schema Zoi.object(%{
                   metric: Zoi.string(),
                   value: Zoi.union([Zoi.float(), Zoi.integer()]),
                   comparison: Zoi.string(),
                   answer: Zoi.string(),
                   caveats: Zoi.list(Zoi.string())
                 })

  agent do
    id :data_analyst_agent
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
    You are a compact data analyst for fixture-backed business metrics.
    Query the local data tools, explain the result plainly, and return structured output.
    """
  end

  capabilities do
    tool Jidoka.Examples.DataAnalyst.Tools.QueryRevenue
    tool Jidoka.Examples.DataAnalyst.Tools.ComparePeriods
  end
end
