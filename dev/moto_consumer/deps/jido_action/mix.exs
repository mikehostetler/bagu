defmodule JidoAction.MixProject do
  use Mix.Project

  @version "2.2.1"
  @source_url "https://github.com/agentjido/jido_action"
  @description "Composable, validated actions for Elixir applications with built-in AI tool integration"

  def vsn do
    @version
  end

  def project do
    [
      app: :jido_action,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),

      # Docs
      name: "Jido Action",
      description: @description,
      source_url: @source_url,
      homepage_url: @source_url,
      package: package(),
      docs: docs(),

      # Coverage
      test_coverage: [
        tool: ExCoveralls
      ],

      # Dialyzer
      dialyzer: [
        plt_local_path: "priv/plts/project.plt",
        plt_core_path: "priv/plts/core.plt",
        plt_add_apps: [:mix]
      ]
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.github": :test,
        "coveralls.lcov": :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.cobertura": :test
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Jido.Action.Application, []}
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support", "test/jido/bus/support"]
  defp elixirc_paths(:dev), do: ["lib", "bench"]
  defp elixirc_paths(_), do: ["lib"]

  defp docs do
    [
      main: "readme",
      api_reference: false,
      source_ref: "v#{@version}",
      source_url: "https://github.com/agentjido/jido_action",
      authors: ["Mike Hostetler <mike.hostetler@gmail.com>"],
      groups_for_extras: [
        "Getting Started": [
          "guides/getting-started.md",
          "guides/your-second-action.md"
        ],
        "Core Concepts": [
          "guides/actions-guide.md",
          "guides/schemas-validation.md",
          "guides/execution-engine.md",
          "guides/instructions-plans.md",
          "guides/error-handling.md"
        ],
        "How-To Guides": [
          "guides/tools-reference.md",
          "guides/ai-integration.md",
          "guides/configuration.md",
          "guides/security.md",
          "guides/testing.md"
        ],
        "Help & Reference": [
          "guides/faq.md",
          "guides/pr-68-triage.md",
          "CHANGELOG.md",
          "LICENSE"
        ]
      ],
      extras: [
        # Home & Project
        {"README.md", title: "Home"},
        # Getting Started
        {"guides/getting-started.md", title: "Getting Started"},
        {"guides/your-second-action.md", title: "Your Second Action"},
        # Core Concepts
        {"guides/actions-guide.md", title: "Actions"},
        {"guides/schemas-validation.md", title: "Schemas & Validation"},
        {"guides/execution-engine.md", title: "Execution Engine"},
        {"guides/instructions-plans.md", title: "Instructions & Plans"},
        {"guides/error-handling.md", title: "Error Handling"},
        # How-To Guides
        {"guides/tools-reference.md", title: "Built-in Tools"},
        {"guides/ai-integration.md", title: "AI Integration"},
        {"guides/configuration.md", title: "Configuration"},
        {"guides/security.md", title: "Security"},
        {"guides/testing.md", title: "Testing"},
        # Help & Reference
        {"guides/faq.md", title: "FAQ"},
        {"guides/pr-68-triage.md", title: "PR #68 Triage"},
        {"CHANGELOG.md", title: "Changelog"},
        {"LICENSE", title: "Apache 2.0 License"}
      ],
      extra_section: "Guides",
      formatters: ["html"],
      skip_undefined_reference_warnings_on: [
        "CHANGELOG.md",
        "LICENSE"
      ],
      groups_for_modules: [
        Core: [
          Jido.Action,
          Jido.Action.Error,
          Jido.Action.Tool,
          Jido.Action.Util
        ],
        "Schemas & Validation": [
          Jido.Action.Runtime,
          Jido.Action.Schema
        ],
        "Execution Engine": [
          Jido.Exec,
          Jido.Exec.Async,
          Jido.Exec.Chain,
          Jido.Exec.Closure,
          Jido.Exec.Compensation,
          Jido.Exec.Retry,
          Jido.Exec.Supervisors,
          Jido.Exec.Telemetry,
          Jido.Exec.Validator
        ],
        "Planning & Workflows": [
          Jido.Plan,
          Jido.Plan.PlanInstruction,
          Jido.Instruction
        ],
        "Actions: Basic Tools": [
          Jido.Tools.Arithmetic,
          Jido.Tools.Basic,
          Jido.Tools.Files,
          Jido.Tools.Workflow
        ],
        "Actions: HTTP & Requests": [
          Jido.Tools.ReqTool
        ],
        "Actions: Advanced": [
          Jido.Tools.ActionPlan,
          Jido.Tools.LuaEval
        ],
        Examples: [
          Jido.Examples.ZoiExample
        ],
        "Error Types": [
          Jido.Action.Error.Config,
          Jido.Action.Error.ConfigurationError,
          Jido.Action.Error.Execution,
          Jido.Action.Error.ExecutionFailureError,
          Jido.Action.Error.Internal,
          Jido.Action.Error.Internal.UnknownError,
          Jido.Action.Error.InternalError,
          Jido.Action.Error.Invalid,
          Jido.Action.Error.InvalidInputError,
          Jido.Action.Error.TimeoutError
        ]
      ]
    ]
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README.md", "LICENSE", "usage-rules.md"],
      maintainers: ["Mike Hostetler"],
      licenses: ["Apache-2.0"],
      links: %{
        "Documentation" => "https://hexdocs.pm/jido_action",
        "GitHub" => @source_url,
        "Website" => "https://jido.run",
        "Discord" => "https://jido.run/discord",
        "Changelog" => "https://github.com/agentjido/jido_action/blob/main/CHANGELOG.md"
      }
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:jason, "~> 1.4"},
      {:nimble_options, "~> 1.1"},
      {:private, "~> 0.1.2"},
      {:telemetry, "~> 1.3"},
      {:telemetry_metrics, "~> 1.1"},
      {:uniq, "~> 0.6.1"},
      {:zoi, "~> 0.17"},
      {:splode, "~> 0.3.0"},

      # Skill & Action Dependencies for examples
      {:abacus, "~> 2.1"},
      {:multigraph, "~> 0.16.1-mg.2"},
      {:lua, "~> 0.3"},
      {:req, "~> 0.5.10"},

      # Development & Test Dependencies
      {:git_ops, "~> 2.9", only: :dev, runtime: false},
      {:git_hooks, "~> 0.8", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test]},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.0", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.21", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18.3", only: [:dev, :test]},
      {:expublish, "~> 2.7", only: [:dev], runtime: false},
      {:mix_test_watch, "~> 1.0", only: [:dev, :test], runtime: false},
      {:mimic, "~> 2.0", only: :test},
      {:spec_led_ex,
       git: "https://github.com/specleddev/specled_ex",
       branch: "main",
       only: [:dev, :test],
       runtime: false},
      {:stream_data, "~> 1.0", only: [:dev, :test]},

      # Code generation
      {:igniter, "~> 0.7", optional: true}
    ]
  end

  defp aliases do
    [
      # Helper to run tests with trace when needed
      # test: "test --trace --exclude flaky",
      test: "test --exclude flaky",

      # Helper to run docs
      docs: "docs -f html --open",

      # Run to check the quality of your code
      q: ["quality"],
      quality: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "credo --min-priority higher",
        "dialyzer"
      ]
    ]
  end
end
