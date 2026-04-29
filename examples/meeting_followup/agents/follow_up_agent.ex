defmodule Jidoka.Examples.MeetingFollowup.Agents.FollowUpAgent do
  @moduledoc false

  use Jidoka.Agent

  @context_schema Zoi.object(%{
                    workspace: Zoi.string() |> Zoi.default("customer-success"),
                    audience: Zoi.string() |> Zoi.default("customer")
                  })

  @output_schema Zoi.object(%{
                   summary: Zoi.string(),
                   decisions: Zoi.list(Zoi.string()),
                   action_items: Zoi.list(Zoi.any()),
                   risks: Zoi.list(Zoi.string()),
                   follow_up_email: Zoi.string()
                 })

  agent do
    id :meeting_followup_agent
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
    You turn meeting notes into an operator-ready follow-up package.
    Extract decisions, action items, risks, and a concise follow-up email.
    """
  end

  capabilities do
    tool Jidoka.Examples.MeetingFollowup.Tools.LoadMeetingNotes
    tool Jidoka.Examples.MeetingFollowup.Tools.ExtractActionItems
  end

  lifecycle do
    output_guardrail Jidoka.Examples.MeetingFollowup.Guardrails.BlockUnsupportedCommitments
  end
end
