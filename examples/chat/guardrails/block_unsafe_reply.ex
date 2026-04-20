defmodule Moto.Examples.Chat.Guardrails.BlockUnsafeReply do
  use Moto.Guardrail, name: "block_unsafe_reply"

  @impl true
  def call(%Moto.Guardrails.Output{outcome: {:ok, result}}) when is_binary(result) do
    if String.contains?(String.downcase(result), "unsafe") do
      {:error, :unsafe_reply_blocked}
    else
      :ok
    end
  end

  def call(%Moto.Guardrails.Output{}), do: :ok
end
