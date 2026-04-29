defmodule Jidoka.Examples.LeadQualification.Tools.EnrichCompany do
  @moduledoc false

  use Jidoka.Tool,
    description: "Returns fixture-backed company enrichment for a lead domain.",
    schema: Zoi.object(%{domain: Zoi.string()})

  @companies %{
    "northwind.example" => %{
      company: "Northwind Finance",
      domain: "northwind.example",
      employees: 1200,
      industry: "financial services",
      technologies: ["Salesforce", "Snowflake", "Slack"],
      recent_signal: "pricing page viewed three times this week"
    },
    "bluebird.example" => %{
      company: "Bluebird Labs",
      domain: "bluebird.example",
      employees: 42,
      industry: "developer tools",
      technologies: ["HubSpot", "Postgres"],
      recent_signal: "downloaded getting started guide"
    }
  }

  @impl true
  def run(%{domain: domain}, _context) do
    key = String.downcase(domain)

    case Map.fetch(@companies, key) do
      {:ok, company} -> {:ok, company}
      :error -> {:error, {:unknown_domain, domain}}
    end
  end
end
