defmodule Jidoka.Examples.PrReviewer.Guardrails.BlockStyleOnlyReview do
  @moduledoc false

  use Jidoka.Guardrail, name: "block_style_only_review"

  @impl true
  def call(%Jidoka.Guardrails.Output{outcome: {:ok, result}}) when is_map(result) do
    findings = Map.get(result, :findings, Map.get(result, "findings", []))
    summary = Map.get(result, :summary, Map.get(result, "summary", ""))

    if findings == [] and String.contains?(String.downcase(summary), "style") do
      {:error, :style_only_review}
    else
      :ok
    end
  end

  def call(%Jidoka.Guardrails.Output{}), do: :ok
end
