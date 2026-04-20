defmodule Moto.Plugins.Memory do
  @moduledoc false

  use Jido.Plugin,
    name: "memory",
    state_key: :__moto_memory_plugin__,
    actions: [],
    schema: Zoi.map() |> Zoi.default(%{}),
    config_schema: Zoi.map() |> Zoi.default(%{}),
    signal_patterns: ["moto.memory.never"],
    singleton: true,
    description: "Moto conversation memory plugin backed by jido_memory.",
    capabilities: [:memory]

  @impl Jido.Plugin
  def mount(agent, config) do
    Jido.Memory.BasicPlugin.mount(agent, config)
  end

  @impl Jido.Plugin
  def signal_routes(_config), do: []

  @impl Jido.Plugin
  def handle_signal(_signal, _context), do: {:ok, :continue}

  @impl Jido.Plugin
  def on_checkpoint(_plugin_state, _context), do: :keep

  @impl Jido.Plugin
  def on_restore(pointer, context), do: Jido.Memory.BasicPlugin.on_restore(pointer, context)
end
