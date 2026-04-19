defmodule MotoConsumer.MixProject do
  use Mix.Project

  def project do
    [
      app: :moto_consumer,
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
      mod: {MotoConsumer.Application, []}
    ]
  end

  defp deps do
    [
      {:ash, "~> 3.24"},
      {:ash_jido, path: "../../../ash_jido"},
      {:jido, path: "../../../jido", override: true},
      {:moto, path: "../.."},
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
