defmodule Moto.Examples.Chat.Plugins.MathPlugin do
  use Moto.Plugin,
    description: "Provides math tools for the demo agent.",
    tools: [Moto.Examples.Chat.Tools.AddNumbers]
end
