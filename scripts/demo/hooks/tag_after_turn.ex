defmodule Moto.Scripts.Demo.Hooks.TagAfterTurn do
  use Moto.Hook, name: "tag_after_turn"

  @impl true
  def call(%Moto.Hooks.AfterTurn{outcome: {:ok, result}}) when is_binary(result) do
    {:ok, {:ok, "[after_turn] #{result}"}}
  end

  def call(%Moto.Hooks.AfterTurn{} = input) do
    {:ok, input.outcome}
  end
end
