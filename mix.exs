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
      {:ash_jido, git: "https://github.com/agentjido/ash_jido.git", branch: "main"},
      {:dotenvy, "~> 1.1"},
      {:jason, "~> 1.4"},
      {:jido, "~> 2.2", override: true},
      {:jido_ai, "~> 2.1", override: true},
      {:jido_mcp, git: "https://github.com/agentjido/jido_mcp.git", branch: "main"},
      {:jido_memory, git: "https://github.com/agentjido/jido_memory.git", branch: "main"},
      {:mdex, "~> 0.12.1"},
      {:plug, "~> 1.18"},
      {:spark, "~> 2.6"},
      {:yaml_elixir, "~> 2.12"},
      {:zoi, "~> 0.17"}
    ]
  end
end
