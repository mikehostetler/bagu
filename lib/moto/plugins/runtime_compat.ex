defmodule Moto.Plugins.RuntimeCompat do
  @moduledoc false

  use Moto.Plugin,
    name: "moto_runtime_compat",
    state_key: :moto_runtime_compat,
    description: "Internal Moto compatibility routes for Jido.AI runtime signals.",
    singleton: true

  @impl Jido.Plugin
  def signal_routes(_config) do
    [
      {"ai.tool.started", Jido.Actions.Control.Noop}
    ]
  end
end
