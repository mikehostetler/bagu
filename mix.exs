defmodule Jidoka.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/mikehostetler/jidoka"
  @description "Experimental developer-friendly LLM agent harness built on Jido and Jido.AI."
  @coverage_threshold 70

  def project do
    [
      app: :jidoka,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      name: "Jidoka",
      description: @description,
      source_url: @source_url,
      homepage_url: @source_url,
      package: package(),
      docs: docs(),
      test_coverage: [
        tool: ExCoveralls,
        summary: [threshold: @coverage_threshold],
        export: "cov",
        ignore_modules: [~r/^JidokaTest\./]
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
      mod: {Jidoka.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ash_jido, git: "https://github.com/agentjido/ash_jido.git", ref: "d10cf6e8292ab7c1a9caf826b641787eb7e864c4"},
      {:dotenvy, "~> 1.1"},
      {:jason, "~> 1.4"},
      {:jido, "~> 2.2", override: true},
      {:jido_ai,
       git: "https://github.com/agentjido/jido_ai.git", ref: "508bcf76ac714bdb101cf7cc13c7dc5f666ec691", override: true},
      {:jido_character,
       git: "https://github.com/agentjido/jido_character.git", ref: "c84532fbb7ba7ccc58e4e76818688208fb59ccac"},
      {:jido_browser, "~> 2.0"},
      {:jido_mcp, git: "https://github.com/agentjido/jido_mcp.git", ref: "ece85aaf745390ee22d00cdbf68bb9d2fa61de3b"},
      {:jido_memory,
       git: "https://github.com/agentjido/jido_memory.git", ref: "2490899522a775f94dca00c91f163bee56dfd86b"},
      {:jido_eval, path: "../jido_eval", only: :test},
      {:jido_runic,
       git: "https://github.com/agentjido/jido_runic.git", ref: "6405a66e32e7d5f0d2246b36b523309e31eac8b1"},
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
        "guides",
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
        "Documentation" => "https://hexdocs.pm/jidoka",
        "Changelog" => "https://hexdocs.pm/jidoka/changelog.html",
        "Website" => "https://jido.run"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras:
        [
          "README.md"
        ] ++
          guide_extras() ++
          [
            "CHANGELOG.md",
            "CONTRIBUTING.md",
            "usage-rules.md"
          ],
      groups_for_extras: [
        Guides: guide_extras(),
        Reference: [
          "usage-rules.md",
          "CHANGELOG.md",
          "CONTRIBUTING.md"
        ]
      ],
      groups_for_modules: [
        Agents: [
          Jidoka.Agent,
          Jidoka.AgentView,
          Jidoka.Agent.View,
          Jidoka.ImportedAgent,
          Jidoka.ImportedAgent.Subagent
        ],
        Workflows: [
          Jidoka.Workflow
        ],
        Runtime: [
          Jidoka,
          Jidoka.Runtime,
          Jidoka.Interrupt,
          Jidoka.Handoff
        ],
        Extensions: [
          Jidoka.Character,
          Jidoka.Tool,
          Jidoka.Plugin,
          Jidoka.Hook,
          Jidoka.Guardrail,
          Jidoka.Web,
          Jidoka.Subagent,
          Jidoka.Handoff.Capability,
          Jidoka.MCP
        ],
        Errors: [
          Jidoka.Error
        ]
      ]
    ]
  end

  defp guide_extras do
    [
      "guides/overview.md",
      "guides/getting-started.md",
      "guides/agents.md",
      "guides/context-and-schema.md",
      "guides/tools-and-capabilities.md",
      "guides/subagents-workflows-handoffs.md",
      "guides/memory.md",
      "guides/characters.md",
      "guides/imported-agents.md",
      "guides/errors-and-debugging.md",
      "guides/evals.md",
      "guides/examples.md",
      "guides/phoenix-liveview.md",
      "guides/production.md"
    ]
  end
end
