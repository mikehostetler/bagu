defmodule JidokaConsumer.Support.Guardrails.SensitiveDataGuardrail do
  @moduledoc false

  use Jidoka.Guardrail, name: "support_sensitive_data"

  @sensitive_terms [
    "api key",
    "card number",
    "credit card number",
    "cvv",
    "cvc",
    "full card",
    "payment token",
    "password",
    "secret"
  ]

  @exfiltration_verbs [
    "display",
    "export",
    "give",
    "list",
    "print",
    "reveal",
    "send",
    "show"
  ]

  @bypass_phrases [
    "bypass verification",
    "ignore policy",
    "skip verification",
    "without verification"
  ]

  @impl true
  def call(%Jidoka.Guardrails.Input{message: message}) when is_binary(message) do
    normalized = String.downcase(message)

    if unsafe_request?(normalized) do
      {:error, :unsafe_support_data_request}
    else
      :ok
    end
  end

  def call(%Jidoka.Guardrails.Input{}), do: :ok

  defp unsafe_request?(message) do
    contains_any?(message, @bypass_phrases) or
      (contains_any?(message, @sensitive_terms) and contains_any?(message, @exfiltration_verbs))
  end

  defp contains_any?(message, terms), do: Enum.any?(terms, &String.contains?(message, &1))
end
