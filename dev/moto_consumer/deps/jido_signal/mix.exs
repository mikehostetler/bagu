defmodule Jido.Signal.MixProject do
  use Mix.Project

  @version "2.1.1"
  @source_url "https://github.com/agentjido/jido_signal"
  @description "Agent Communication Envelope and Utilities"

  def vsn do
    @version
  end

  def project do
    [
      app: :jido_signal,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),

      # Docs
      name: "Jido Signal",
      description: @description,
      source_url: @source_url,
      homepage_url: @source_url,
      package: package(),
      docs: docs(),

      # Coverage
      test_coverage: [
        tool: ExCoveralls,
        summary: [threshold: 90],
        export: "cov",
        ignore_modules: [~r/^JidoTest\./]
      ],

      # Dialyzer
      dialyzer: [
        plt_local_path: "priv/plts/project.plt",
        plt_core_path: "priv/plts/core.plt",
        ignore_warnings: "dialyzer.ignore-warnings"
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

  def application do
    [
      extra_applications: [:logger],
      mod: {Jido.Signal.Application, []}
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "CONTRIBUTING.md",
        "LICENSE",
        "guides/getting-started.md",
        "guides/signals-and-dispatch.md",
        "guides/event-bus.md",
        "guides/signal-router.md",
        "guides/signal-extensions.md",
        "guides/signal-journal.md",
        "guides/serialization.md",
        "guides/advanced.md"
      ],
      groups_for_extras: [
        Guides: ~r/guides\/.*/
      ],
      groups_for_modules: [
        "Core Signal": [
          Jido.Signal,
          Jido.Signal.Error,
          Jido.Signal.ID,
          Jido.Signal.Util
        ],
        "Signal Routing": [
          Jido.Signal.Router,
          Jido.Signal.Router.Engine,
          Jido.Signal.Router.HandlerInfo,
          Jido.Signal.Router.Inspect,
          Jido.Signal.Router.NodeHandlers,
          Jido.Signal.Router.PatternMatch,
          Jido.Signal.Router.Route,
          Jido.Signal.Router.Router,
          Jido.Signal.Router.TrieNode,
          Jido.Signal.Router.Validator,
          Jido.Signal.Router.WildcardHandlers
        ],
        "Event Bus": [
          Jido.Signal.Bus,
          Jido.Signal.Bus.Middleware,
          Jido.Signal.Bus.MiddlewarePipeline,
          Jido.Signal.Bus.PersistentSubscription,
          Jido.Signal.Bus.RecordedSignal,
          Jido.Signal.Bus.Snapshot,
          Jido.Signal.Bus.Snapshot.SnapshotData,
          Jido.Signal.Bus.Snapshot.SnapshotRef,
          Jido.Signal.Bus.State,
          Jido.Signal.Bus.Stream,
          Jido.Signal.Bus.Subscriber,
          Jido.Signal.Bus.Middleware.Logger
        ],
        "Signal Dispatch": [
          Jido.Signal.Dispatch,
          Jido.Signal.Dispatch.Adapter,
          Jido.Signal.Dispatch.CircuitBreaker,
          Jido.Signal.Dispatch.ConsoleAdapter,
          Jido.Signal.Dispatch.Http,
          Jido.Signal.Dispatch.LoggerAdapter,
          Jido.Signal.Dispatch.Named,
          Jido.Signal.Dispatch.NoopAdapter,
          Jido.Signal.Dispatch.PidAdapter,
          Jido.Signal.Dispatch.PubSub,
          Jido.Signal.Dispatch.Webhook
        ],
        "Signal Journal": [
          Jido.Signal.Journal,
          Jido.Signal.Journal.Adapters.ETS,
          Jido.Signal.Journal.Adapters.InMemory,
          Jido.Signal.Journal.Adapters.Mnesia,
          Jido.Signal.Journal.Persistence
        ],
        Serialization: [
          Jido.Signal.Serialization.Config,
          Jido.Signal.Serialization.ErlangTermSerializer,
          Jido.Signal.Serialization.JsonDecoder,
          Jido.Signal.Serialization.JsonSerializer,
          Jido.Signal.Serialization.ModuleNameTypeProvider,
          Jido.Signal.Serialization.MsgpackSerializer,
          Jido.Signal.Serialization.Serializer,
          Jido.Signal.Serialization.TypeProvider
        ],
        "System Infrastructure": [
          Jido.Signal.Application,
          Jido.Signal.Registry,
          Jido.Signal.Registry.Subscription
        ],
        "Errors & Exceptions": [
          Jido.Signal.Error.DispatchError,
          Jido.Signal.Error.Execution,
          Jido.Signal.Error.ExecutionFailureError,
          Jido.Signal.Error.Internal,
          Jido.Signal.Error.Internal.UnknownError,
          Jido.Signal.Error.InternalError,
          Jido.Signal.Error.Invalid,
          Jido.Signal.Error.InvalidInputError,
          Jido.Signal.Error.Routing,
          Jido.Signal.Error.RoutingError,
          Jido.Signal.Error.Timeout,
          Jido.Signal.Error.TimeoutError
        ]
      ]
    ]
  end

  def package do
    [
      files: ["lib", "mix.exs", "README*", "LICENSE*", "CHANGELOG*", "usage-rules.md"],
      maintainers: ["Mike Hostetler"],
      licenses: ["Apache-2.0"],
      links: %{
        "Documentation" => "https://hexdocs.pm/jido_signal",
        "GitHub" => @source_url,
        "Website" => "https://jido.run",
        "Discord" => "https://jido.run/discord",
        "Changelog" => "https://github.com/agentjido/jido_signal/blob/main/CHANGELOG.md"
      }
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Deps
      {:jason, "~> 1.4"},
      {:msgpax, "~> 2.3"},
      {:nimble_options, "~> 1.1"},
      {:phoenix_pubsub, "~> 2.1"},
      {:telemetry, "~> 1.3"},
      {:uniq, "~> 0.6.1"},
      {:splode, "~> 0.3.0"},
      {:zoi, "~> 0.17.1"},
      {:memento, "~> 0.5.0"},
      {:fuse, "~> 2.5"},
      {:spec_led_ex, github: "specleddev/specled_ex", only: [:dev, :test], runtime: false},

      # Development & Test Dependencies
      {:git_ops, "~> 2.9", only: :dev, runtime: false},
      {:git_hooks, "~> 0.8", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test]},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.21", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18.3", only: [:dev, :test]},
      {:castore, "~> 1.0", only: [:dev, :test]},
      {:expublish, "~> 2.7", only: [:dev], runtime: false},
      {:mix_test_watch, "~> 1.4.0", only: :dev, runtime: false},
      {:mimic, "~> 2.0", only: :test},
      {:stream_data, "~> 1.0", only: [:dev, :test]},
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
