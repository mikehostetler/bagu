defmodule Picosat.MixProject do
  use Mix.Project

  def project do
    [
      app: :picosat_elixir,
      version: "0.2.3",
      elixir: "~> 1.7",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      compilers: [:elixir_make | Mix.compilers()],
      make_clean: ["clean"],
      make_targets: ["all"],
      elixirc_paths: elixirc_paths(Mix.env()),
      preferred_cli_env: preferred_cli_env(),
      description: "Bindings for the PicoSAT SAT solver",
      package: package(),
    ]
  end

  defp package do
    [
      files: [
        "lib", 
        "src", 
        "c_src/picosat.h", 
        "c_src/picosat.c", 
        "c_src/picosat_nif.c", 
        "priv/.gitkeep", 
        "mix.exs", 
        "Makefile", 
        "Makefile.win", 
        "README.md", 
        "LICENSE.md"
      ],
      maintainers: ["Paul Schoenfelder"],
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub": "https://github.com/bitwalker/picosat_elixir",
        "Issues": "https://github.com/bitwalker/picosat_elixir/issues",
      }
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: []
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:elixir_make, "~> 0.6", runtime: false},
      {:ex_doc, ">= 0.0.0", only: [:docs]},
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp preferred_cli_env do
    [
      docs: :docs,
      "hex.publish": :docs,
    ]
  end
end
