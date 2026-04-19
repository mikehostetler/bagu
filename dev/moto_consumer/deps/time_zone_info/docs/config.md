# Config

Add the following line to use `TimeZoneInfo` per default in the project.
```
config :elixir, :time_zone_database, TimeZoneInfo.TimeZoneDatabase
```

## Enable automated updates

The automated update uses the default `Downloader`, and this one uses
[`Mint`](https://github.com/elixir-mint/mint). Therefore the following
dependencies are needed in `mix.exs`.
```
defp deps do
  [
    ...
    {:castore, "~> 0.1.0"},
    {:mint, "~> 1.0"},
    ...
  ]
end
```
The config has to be extended with:
```
config :time_zone_info, update: :daily
```

## Custom downloader

It is also possible to use your own downloader. This requires an implementation
of the behaviour `TimeZoneInfo.Downloader`. The custom downloader has to be
specified in the config.
```
config :time_zone_info, [
  update: :daily,
  downloader: [
    module: MyApp.TimeZonInfo.Downloader,
    uri: "https://data.iana.org/time-zones/tzdata-latest.tar.gz",
    mode: :iana,
    headers: [
      {"Content-Type", "application/tar+gzip"},
      {"User-Agent", "Elixir.TimeZoneInfo.Mint"}
    ]
  ],
]
```

The option `update` specifies the update interval. Possible values are `:daily`
and `:disabled` to disable the automated update.

The keys `uri` and `headers` containing to download the data.

The key `mode` can contain `:iana`, `:etf`, or `:ws` and indicates whether they
data are delivered in IANA format (.tar.gz) or in zipped ETF
([External Term Format](http://erlang.org/doc/apps/erts/erl_ext_dist.html)).

In `:ws` mode, the request for the data contains query parameters. The parameters
are containing the configuration:
- `files[]`: A list of IANA files which are used to generate the
  `TimeZoneInfo.data`.
- `time_zones[]`: A list of time zones. These parameters do not apply if no
  time zones are specified.
- `lookahead`

The response format in `:ws` mode is the same as in `:etf` mode.

## Time zone manipulation

`TimeZoneInfo` provides some configuration options to select a subset form the
available time zones and the size of the generated periods table.

```
config :time_zone_info,
  ...
  files: ~w(europe asia),
  time_zones: ~w(Europe Asia/Istanbul),
  lookahead: 5
```

`files:`\
Default: `["africa", "antarctica", "asia", "australasia", "backward",
"etcetera", "europe", "northamerica", "southamerica")`\
This option specifies which files are parsed from the IANA data. The files
`europe`, `asia`, etc are self-explanatory. The file `ecetera` contains time
zones like `Etc/UTC`, `Etc/Zulu`, `Etc/GMT+1`, etc. The `backward` file contains
obsolete time zones. If you do not need the obsolete time zones, configure a
list without the `backward` file.
**Note:** The configuration `:files` takes no effect if `update: :disabled` is
set.

`time_zones:`\
Default: `:all`\
With `time_zones:` you can determine which time zones should be used. This
configuration expected a list of time zone names and/or areas like
`["Asia", "Europe/Berlin"]`. In this example all time zones in the area Asia and
the time zone "Europe/Berlin" are available.
If a time zone link matches the `time_zones` configuration, the linked time zone
will be also be available. For example, if you set `time_zones: ["Europe/Jersey"]`
then the time zone `Europe/London` is also available because `Europe/Jersey`
links this time zone.

`lookahead:`\
Default: `5`\
The `lookahead` specifies for how many years from now the periods will be
calculated.\
**Note:** They configuration `:lookahead` takes no effect if `update: :disabled`
is set.

## Data persistence

`TimeZoneInfo` has two implementations of the behaviour
`TimeZoneInfo.DataPersistence` to persist data.

`TimeZoneInfo.DataPersistence.Priv` is used in the default configuration.
```
config :time_zone_info,
  ...
  data_persistence: TimeZoneInfo.DataPersistence.Priv,
  priv: [path: "data.etf"]
```
This module is intended for simple configurations. The specified `data.etf` is
part of the `TimeZoneInfo` package and contains the transformed data from the
actual IANA time zone DB.

`TimeZoneInfo.DataPersistence.FileSystem` stores the data in a file to be
specified.
```
config :time_zone_info,
  ...
  data_persistence: TimeZoneInfo.DataPersistence.FileSystem,
  file_system: [path: "data/tzi.etf"]
```

## The data store

`TimeZoneInfo` provides two methods to store data at runtime.
The data can be stored either with `:persistent_term` or with `:ets`. The option
`data_store` holds this configuration. With `data_store: :detect` (default) the
method with `:persistent_term` will be used if `:persitent_term` is available
(OTP >= 21.2). To set a method explicitly use
`data_store: TimeZoneInfo.DataStore.PersistentTerm` or
`data_store: TimeZoneInfo.DataStore.ErlangTermStorage`.

## No runtime config, no delete

It is not recomented to update the configuration at runtime. Becaus the data
in runtime will just be updated but never deleted. That means if you change
`time_zones: :all` to `time_zones: ["Europe"]` then **all** time zones are
available after an update.

This is not a problem for the automated update. Because all period tables will
be updated.
