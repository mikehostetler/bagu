defmodule Moto.Scripts.Demo.Plugins.MathPlugin do
  use Moto.Plugin,
    description: "Provides math tools for the demo agent.",
    tools: [Moto.Scripts.Demo.Tools.AddNumbers]
end
