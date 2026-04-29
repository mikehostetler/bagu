defmodule Jidoka.Examples.SupportTriage.Guardrails.BlockPaymentSecrets do
  @moduledoc false

  use Jidoka.Guardrail, name: "block_payment_secrets"

  @impl true
  def call(%Jidoka.Guardrails.Input{message: message}) when is_binary(message) do
    if String.match?(message, ~r/\b(?:\d[ -]*?){13,16}\b/) do
      {:error, :payment_secret_detected}
    else
      :ok
    end
  end
end
