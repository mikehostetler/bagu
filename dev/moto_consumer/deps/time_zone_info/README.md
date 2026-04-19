# TimeZoneInfo
[![Hex.pm: version](https://img.shields.io/hexpm/v/time_zone_info.svg?style=flat-square)](https://hex.pm/packages/time_zone_info)
[![GitHub: CI status](https://img.shields.io/github/actions/workflow/status/hrzndhrn/time_zone_info/ci.yml?branch=main&style=flat-square)](https://github.com/hrzndhrn/time_zone_info/actions)
[![Coveralls: coverage](https://img.shields.io/coveralls/github/hrzndhrn/time_zone_info?style=flat-square)](https://coveralls.io/github/hrzndhrn/time_zone_info)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square)](https://github.com/hrzndhrn/time_zone_info/blob/main/LICENSE.md)

Time zone support for Elixir by using the
[IANA Time Zone Database](https://www.iana.org/time-zones).

## Installation

The package can be installed by adding `time_zone_info` to your list of
dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:time_zone_info, "~> 0.7"}
  ]
end
```

## Usage

After installation, `TimeZoneInfo` can be used as follows.
```elixir
iex> TimeZoneInfo.iana_version
"2026a"
iex> TimeZoneInfo.time_zones() |> Enum.take(3)
["Africa/Abidjan", "Africa/Accra", "Africa/Addis_Ababa"]
iex> TimeZoneInfo.TimeZoneDatabase.time_zone_periods_from_wall_datetime(~N[2021-09-23 09:56:00], "Europe/Berlin")
{:ok,
 %{
   std_offset: 3600,
   utc_offset: 3600,
   wall_period: {~N[2021-03-28 03:00:00], ~N[2021-10-31 03:00:00]},
   zone_abbr: "CEST"
 }}
```

In combination with `DateTime` and `Calendar`:
```elixir
iex> {:ok, berlin} = DateTime.from_naive(
...>   ~N[2020-03-29 01:30:00],
...>   "Europe/Berlin",
...>    TimeZoneInfo.TimeZoneDatabase)
{:ok, #DateTime<2020-03-29 01:30:00+01:00 CET Europe/Berlin>}
iex> Calendar.put_time_zone_database(TimeZoneInfo.TimeZoneDatabase)
:ok
iex> DateTime.shift_zone(berlin, "America/New_York")
{:ok, #DateTime<2020-03-28 20:30:00-04:00 EDT America/New_York>}
```

Instead of the line
`Calendar.put_time_zone_database(TimeZoneInfo.TimeZoneDatabase)` you can also
specify the following entry in the configuration.
```elixir
config :elixir, :time_zone_database, TimeZoneInfo.TimeZoneDatabase
```

## Config

`TimeZoneInfo` has several configuration options:
+ Enable automated updates from the IANA tzdb
+ Setup for how many years rules will be precalculated
+ Selection of supported time zones

For more information how to configure `TimeZoneInfo` see
[Config](https://hexdocs.pm/time_zone_info/config.html).

## Default Time Zone Data

The default configuration of `TimeZoneInfo` is `update: :disabled`. In this
case, the IANA database in version `2026a` with a `lookahead` of 15 years is in
use.

If a time zone has continuation rules, the periods after the lookahead are
calculating by these rules. Note, these calculations are much more expensive as
the determination of periods inside the prepared time span.

## Benchmarks

The benchmarks can be executed with `mix bench`.

Benchmarks:
+ This [benchmark](https://github.com/hrzndhrn/time_zone_info/blob/main/bench/time_zone_database_bench.md)
  compares `TimeZoneInfo` with `Tzdata`, `Tz` and `Zoneinfo`.

+ This [benchmark](https://github.com/hrzndhrn/time_zone_info/blob/main/bench/stores_bench.md)
  compares the different `TimeZoneInfo.DataStore`s.

+ This [benchmark](https://github.com/hrzndhrn/time_zone_info/blob/main/bench/transform_bench.md)
  measures the speed of transforming the raw IANA data to the required format at
  runtime.

## Differences to Tzdata and Tz

There are some differences to `Tzdata` and `Tz`. The list shows differences to
`Tzdata` and/or `Tz`.

- Use of `:persitent_term` with an optional use of `:ets`.
- Persisting data in
  [External Term Format](http://erlang.org/doc/apps/erts/erl_ext_dist.html)
- The data persisting is customizable by the behaviour
  `TimeZoneInfo.DataPersistence`.
- Optional download of time zone data in `TimeZoneInfo` format.
- The download is customizable by the behaviour `TimeZoneInfo.Downloader`.
- Filter time zones per config.
- Optional listener that will be called on updates.
- `TimeZoneInfo` calculates periods in the far future by continuation rules.
  Except for time zones that have daylight saving times for Ramadan.

## References

The home of the IANA Time Zone Database: https://www.iana.org/time-zones

Links:
- [Time zone](https://en.wikipedia.org/wiki/Time_zone) - Wikipedia
- [**time**and**date**.com](https://www.timeanddate.com/)
- [WorldTimeServer.com](https://www.worldtimeserver.com/)

Other Elixir implementations:
- [tzdata](https://github.com/lau/tzdata) - Tzdata is a parser and library for
  the tz database.
- [tz](https://github.com/mathieuprog/tz) - Time zone support for Elixir
- [zoneinfo](https://github.com/smartrent/zoneinfo) - Elixir time zone support
  for your OS-supplied zoneinfo files

Other implementations:
- [DateTime::TimeZone](https://github.com/houseabsolute/DateTime-TimeZone) - Perl
  - `TimeZoneInfo` use this module as a checker in the tests.
- [NodaTime](https://nodatime.org/) - A better date and time API for .NET
  - `TimeZonInfo` use some data from this
    [site](https://nodatime.org/tzvalidate/generate?version=2019c) in the tests.
