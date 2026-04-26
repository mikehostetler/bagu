defmodule JidokaConsumer.MixProject do
  use Mix.Project

  def project do
    [
      app: :jidoka_consumer,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {JidokaConsumer.Application, []}
    ]
  end

  defp deps do
    [
      {:ash, "~> 3.24"},
      {:ash_jido,
       git: "https://github.com/agentjido/ash_jido.git",
       ref: "d10cf6e8292ab7c1a9caf826b641787eb7e864c4",
       override: true},
      {:jido, "~> 2.2", override: true},
      {:jidoka, path: "../.."},
      {:bandit, "~> 1.5"},
      {:dotenvy, "~> 1.1"},
      {:floki, ">= 0.38.0"},
      {:jason, "~> 1.4"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:mdex, "~> 0.12.1"},
      {:phoenix, "~> 1.8"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_view, "~> 1.1"},
      {:phoenix_pubsub, "~> 2.1"},
      {:picosat_elixir, "~> 0.2", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get"],
      test: ["test"]
    ]
  end
end
