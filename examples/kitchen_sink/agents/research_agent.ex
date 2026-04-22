defmodule Moto.Examples.KitchenSink.Agents.ResearchAgent do
  use Moto.Agent

  agent do
    name("kitchen_research_agent")
    model(:fast)

    schema(
      Zoi.object(%{
        tenant: Zoi.string() |> Zoi.optional(),
        channel: Zoi.string() |> Zoi.default("kitchen_sink"),
        session: Zoi.string() |> Zoi.optional(),
        specialty: Zoi.string() |> Zoi.default("research")
      })
    )

    system_prompt("""
    You are a research specialist used by the Moto kitchen sink showcase.
    Return concise factual notes.
    Do not mention orchestration internals.
    """)
  end
end
