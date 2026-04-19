defmodule Moto.Scripts.Demo.Hooks.TagAfterTurn do
  use Moto.Hook, name: "tag_after_turn"

  @impl true
  def call(%Moto.Hooks.AfterTurn{outcome: {:ok, result}} = input) when is_binary(result) do
    tenant = Map.get(input.context, :tenant, Map.get(input.context, "tenant", "unknown"))
    {:ok, {:ok, "[after_turn tenant=#{tenant}] #{result}"}}
  end

  def call(%Moto.Hooks.AfterTurn{} = input) do
    {:ok, input.outcome}
  end
end
