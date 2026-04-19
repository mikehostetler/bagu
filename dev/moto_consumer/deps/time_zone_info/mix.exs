defmodule TimeZoneInfo.MixProject do
  use Mix.Project

  def project do
    [
      app: :time_zone_info,
      version: "0.7.12",
      elixir: "~> 1.13",
      name: "TimeZoneInfo",
      description: description(),
      start_permanent: Mix.env() == :prod,
      build_embedded: true,
      deps: deps(),
      aliases: aliases(),
      test_coverage: [tool: ExCoveralls],
      dialyzer: dialyzer(),
      source_url: "https://github.com/hrzndhrn/time_zone_info",
      docs: docs(),
      package: package(),
      test_ignore_filters: [~r'test/support/.*']
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {TimeZoneInfo.Application, []},
      env: env()
    ]
  end

  def cli do
    [
      preferred_envs: [
        carp: :test,
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.github": :test
      ]
    ]
  end

  def description do
    "Time zone support for Elixir by using the IANA tz database."
  end

  defp env do
    [
      files: [
        "africa",
        "antarctica",
        "asia",
        "australasia",
        "backward",
        "etcetera",
        "europe",
        "northamerica",
        "southamerica"
      ],
      time_zones: :all,
      lookahead: 15,
      data_store: :detect,
      update: :disabled,
      listener: TimeZoneInfo.Listener.ErrorLogger,
      downloader: [
        module: TimeZoneInfo.Downloader.Mint,
        uri: "https://data.iana.org/time-zones/tzdata-latest.tar.gz",
        mode: :iana,
        headers: [
          {"content-type", "application/gzip"},
          {"user-agent", "Elixir.TimeZoneInfo.Mint"}
        ]
      ],
      data_persistence: TimeZoneInfo.DataPersistence.Priv,
      priv: [data: "data.etf", timestamp: "timestamp.txt"]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "docs/config.md",
        "CHANGELOG.md"
      ],
      skip_undefined_reference_warnings_on: [
        "CHANGELOG.md"
      ],
      groups_for_modules: [
        Behaviours: [
          TimeZoneInfo.DataPersistence,
          TimeZoneInfo.DataStore,
          TimeZoneInfo.Downloader,
          TimeZoneInfo.Listener
        ],
        DataPersistence: [
          TimeZoneInfo.DataPersistence.Priv,
          TimeZoneInfo.DataPersistence.FileSystem
        ],
        DataStore: [
          TimeZoneInfo.DataStore.ErlangTermStorage,
          TimeZoneInfo.DataStore.PersistentTerm
        ],
        Downlaoder: [
          TimeZoneInfo.Downloader.Mint
        ],
        Listener: [
          TimeZoneInfo.Listener.ErrorLogger,
          TimeZoneInfo.Listener.Logger
        ],
        "Parser/Tranformer": [
          TimeZoneInfo.IanaParser,
          TimeZoneInfo.Transformer,
          TimeZoneInfo.Transformer.Abbr,
          TimeZoneInfo.Transformer.Rule,
          TimeZoneInfo.Transformer.RuleSet,
          TimeZoneInfo.Transformer.ZoneState
        ]
      ]
    ]
  end

  defp dialyzer do
    [
      ignore_warnings: ".dialyzer_ignore.exs",
      plt_add_apps: [:mint, :nimble_parsec],
      plt_file: {:no_warn, "test/support/plts/dialyzer.plt"},
      flags: [:unmatched_returns]
    ]
  end

  defp aliases do
    [
      "tzi.update": ["run scripts/update.exs"],
      test: ["test --no-start"],
      carp: ["test --no-start --seed 0 --max-failures 1"]
    ]
  end

  defp deps do
    [
      {:nimble_parsec, "~> 1.3", runtime: false},

      # optional
      {:castore, "~> 1.0", optional: true},
      {:mint, "~> 1.0", optional: true},

      # dev and test
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.1", only: :dev, runtime: false},
      {:ex_cldr_calendars_coptic, "~> 1.0", only: [:dev, :test]},
      {:ex_doc, "~> 0.21", only: :dev, runtime: false},
      {:excoveralls, "~> 0.10", only: :test, runtime: false},
      {:hackney, "~> 1.15", only: [:test, :dev], runtime: false},
      {:mox, "~> 1.0", only: :test},
      {:plug_cowboy, "~> 2.5", only: [:dev, :test]},
      {:recode, "~> 0.5", only: :dev},
      {:stream_data, "~> 1.1", only: [:dev, :test], runtime: false},

      # benchee
      {:benchee_dsl, "~> 0.5", only: :dev},
      {:benchee_markdown, "~> 0.3", only: :dev},

      # other time zone DBs
      {:nerves_time_zones, "~> 0.2", only: [:dev], runtime: false},
      {:tz, "~> 0.8", only: [:test, :dev], runtime: false},
      {:tzdata, "~> 1.0", only: [:test, :dev], runtime: false},
      {:zoneinfo, "~> 0.1.3", only: [:dev], runtime: false}
    ]
  end

  defp package do
    [
      maintainers: ["Marcus Kruse"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/hrzndhrn/time_zone_info"},
      files: [
        "lib",
        "priv",
        "mix.exs",
        "README*",
        "LICENSE*",
        "docs/config.md"
      ]
    ]
  end
end
