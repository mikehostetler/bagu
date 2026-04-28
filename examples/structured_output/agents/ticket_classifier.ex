defmodule Jidoka.Examples.StructuredOutput.Agents.TicketClassifier do
  @moduledoc false

  use Jidoka.Agent

  @output_schema Zoi.object(%{
                   category: Zoi.enum([:billing, :technical, :account]),
                   confidence: Zoi.float(),
                   summary: Zoi.string()
                 })

  agent do
    id :structured_output_ticket_classifier

    output do
      schema @output_schema
      retries(1)
      on_validation_error(:repair)
    end
  end

  defaults do
    model :fast

    instructions """
    Classify support tickets for routing.
    Return a short summary and a confidence score.
    """
  end
end
