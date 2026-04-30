defmodule Jidoka.Agent.Dsl.Sections.Schedules do
  @moduledoc false

  alias Jidoka.Agent.Dsl.Schedule

  @spec schedule_entity() :: Spark.Dsl.Entity.t()
  def schedule_entity do
    %Spark.Dsl.Entity{
      name: :schedule,
      describe: """
      Register a first-class Jidoka schedule for this agent.
      """,
      target: Schedule,
      args: [:name],
      schema: [
        name: [
          type: :atom,
          required: true,
          doc: "Local schedule name. This becomes the default public schedule id."
        ],
        cron: [
          type: :string,
          required: true,
          doc: "Cron expression for this schedule."
        ],
        timezone: [
          type: :string,
          required: false,
          default: Jidoka.Schedule.default_timezone(),
          doc: "Timezone used to evaluate the cron expression."
        ],
        prompt: [
          type: :any,
          required: true,
          doc: "Scheduled agent prompt as a string or MFA tuple."
        ],
        context: [
          type: :any,
          required: false,
          default: %{},
          doc: "Runtime context as a map, keyword list, or MFA tuple."
        ],
        conversation: [
          type: :string,
          required: false,
          doc: "Optional conversation id for the scheduled turn."
        ],
        agent_id: [
          type: :any,
          required: false,
          doc: "Optional runtime agent id. Defaults to the schedule id."
        ],
        overlap: [
          type: {:in, [:skip, :allow]},
          required: false,
          default: :skip,
          doc: "Overlap policy when a previous run has not completed."
        ],
        timeout: [
          type: :integer,
          required: false,
          default: 30_000,
          doc: "Chat timeout in milliseconds."
        ],
        enabled?: [
          type: :boolean,
          required: false,
          default: true,
          doc: "Whether the schedule should be enabled when registered."
        ]
      ]
    }
  end

  @spec section() :: Spark.Dsl.Section.t()
  def section do
    %Spark.Dsl.Section{
      name: :schedules,
      describe: """
      Declare recurring scheduled turns for this agent.
      """,
      entities: [schedule_entity()]
    }
  end
end
