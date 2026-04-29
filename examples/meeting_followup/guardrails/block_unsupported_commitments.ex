defmodule Jidoka.Examples.MeetingFollowup.Guardrails.BlockUnsupportedCommitments do
  @moduledoc false

  use Jidoka.Guardrail, name: "block_unsupported_commitments"

  @impl true
  def call(%Jidoka.Guardrails.Output{outcome: {:ok, result}}) when is_map(result) do
    email = Map.get(result, :follow_up_email, Map.get(result, "follow_up_email", ""))

    if String.contains?(String.downcase(email), "guarantee") do
      {:error, :unsupported_commitment}
    else
      :ok
    end
  end

  def call(%Jidoka.Guardrails.Output{}), do: :ok
end
