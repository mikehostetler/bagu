defmodule Moto.MixProject do
  use Mix.Project

  def project do
    [
      app: :moto,
      version: "0.1.0",
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Moto.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ash_jido, path: "../ash_jido"},
      {:dotenvy, "~> 1.1"},
      {:jason, "~> 1.4"},
      {:jido, path: "../jido", override: true},
      {:jido_ai, path: "../jido_ai", override: true},
      {:jido_memory,
       git: "https://github.com/agentjido/jido_memory.git", branch: "main", override: true},
      {:spark, "~> 2.6"},
      {:yaml_elixir, "~> 2.12"},
      {:zoi, "~> 0.17"}
    ]
  end
end
