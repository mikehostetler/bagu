defmodule Moto.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/mikehostetler/moto"
  @description "Experimental developer-friendly LLM agent DSL built on Jido and Jido.AI."
  @coverage_threshold 70

  def project do
    [
      app: :moto,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      name: "Moto",
      description: @description,
      source_url: @source_url,
      homepage_url: @source_url,
      package: package(),
      docs: docs(),
      test_coverage: [
        tool: ExCoveralls,
        summary: [threshold: @coverage_threshold],
        export: "cov",
        ignore_modules: [~r/^MotoTest\./]
      ],
      dialyzer: [
        plt_add_apps: [:mix, :llm_db],
        plt_local_path: "priv/plts/project.plt",
        plt_core_path: "priv/plts/core.plt"
      ]
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.github": :test,
        "coveralls.html": :test
      ]
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
      {:jido_ai, git: "https://github.com/agentjido/jido_ai.git", branch: "main", override: true},
      {:jido_mcp, git: "https://github.com/agentjido/jido_mcp.git", branch: "main"},
      {:jido_memory, git: "https://github.com/agentjido/jido_memory.git", branch: "main"},
      {:mdex, "~> 0.12.1"},
      {:plug, "~> 1.18"},
      {:spark, "~> 2.6"},
      {:yaml_elixir, "~> 2.12"},
      {:zoi, "~> 0.17"},
      {:splode, "~> 0.3.0"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.21", only: :dev, runtime: false},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18", only: [:dev, :test]},
      {:git_hooks, "~> 0.8", only: [:dev, :test], runtime: false},
      {:git_ops, "~> 2.9", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get"],
      install_hooks: ["git_hooks.install"],
      q: ["quality"],
      quality: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "credo --min-priority higher",
        "dialyzer",
        "doctor --raise"
      ]
    ]
  end

  defp package do
    [
      files: [
        "lib",
        "examples",
        "mix.exs",
        "README.md",
        "CHANGELOG.md",
        "CONTRIBUTING.md",
        "LICENSE",
        "usage-rules.md"
      ],
      maintainers: ["Mike Hostetler"],
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @source_url,
        "Documentation" => "https://hexdocs.pm/moto",
        "Changelog" => "https://hexdocs.pm/moto/changelog.html",
        "Website" => "https://jido.run"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: [
        "README.md",
        "CHANGELOG.md",
        "CONTRIBUTING.md",
        "usage-rules.md"
      ],
      groups_for_extras: [
        Guides: ["usage-rules.md"]
      ],
      groups_for_modules: [
        Agents: [
          Moto.Agent,
          Moto.ImportedAgent,
          Moto.ImportedAgent.Subagent
        ],
        Runtime: [
          Moto,
          Moto.Runtime,
          Moto.Interrupt
        ],
        Extensions: [
          Moto.Tool,
          Moto.Plugin,
          Moto.Hook,
          Moto.Guardrail,
          Moto.Subagent,
          Moto.MCP
        ],
        Errors: [
          Moto.Error
        ]
      ]
    ]
  end
end
