defmodule Jidoka.Examples.ResearchBrief.Tools.LoadSources do
  @moduledoc false

  use Jidoka.Tool,
    description: "Loads fixture-backed source snippets for a research topic.",
    schema: Zoi.object(%{topic: Zoi.string()})

  @impl true
  def run(%{topic: topic}, _context) do
    if String.contains?(String.downcase(topic), "agent observability") do
      {:ok,
       %{
         topic: "agent observability",
         sources: [
           %{
             id: "S1",
             title: "Tracing agent runs",
             snippet: "Timelines help developers inspect tool calls and model turns."
           },
           %{id: "S2", title: "Structured outputs", snippet: "Typed final outputs make downstream automation safer."},
           %{
             id: "S3",
             title: "Human approvals",
             snippet: "Interrupts are useful when tools perform risky side effects."
           }
         ]
       }}
    else
      {:error, {:unknown_topic, topic}}
    end
  end
end
