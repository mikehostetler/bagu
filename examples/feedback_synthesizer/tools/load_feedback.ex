defmodule Jidoka.Examples.FeedbackSynthesizer.Tools.LoadFeedback do
  @moduledoc false

  use Jidoka.Tool,
    description: "Loads a fixture-backed batch of customer feedback.",
    schema: Zoi.object(%{batch_id: Zoi.string()})

  @batches %{
    "Q2-VOICE" => %{
      batch_id: "Q2-VOICE",
      comments: [
        "The trace timeline helped us explain tool calls to support leads.",
        "We need exports for structured outputs.",
        "Setup felt easy, but debugging failed tool calls needs clearer UX.",
        "Please add better examples for approvals and incident workflows."
      ]
    }
  }

  @impl true
  def run(%{batch_id: batch_id}, _context) do
    case Map.fetch(@batches, batch_id) do
      {:ok, batch} -> {:ok, batch}
      :error -> {:error, {:unknown_feedback_batch, batch_id}}
    end
  end
end
