defmodule JidokaConsumer.Support.Agents.WriterSpecialistAgent do
  @moduledoc false

  use Jidoka.Agent

  @context_fields %{
    channel: Zoi.string() |> Zoi.default("support_chat"),
    session: Zoi.string() |> Zoi.optional(),
    account_id: Zoi.string() |> Zoi.optional()
  }

  agent do
    id :writer_specialist
    description "Specialist for drafting support-ready copy."
    schema Zoi.object(@context_fields)
  end

  defaults do
    model :fast

    instructions """
    You write calm, direct customer-support copy.
    Keep the tone professional and brief.
    Return the drafted text only unless the prompt explicitly asks for structure.
    """
  end
end
