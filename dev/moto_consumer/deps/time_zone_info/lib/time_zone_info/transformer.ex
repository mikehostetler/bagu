defmodule TimeZoneInfo.Transformer do
  @moduledoc """
  The `Transformer` transfers the parsed IANA data into the required format for
  `TimeZoneInfo`.
  """

  alias TimeZoneInfo.IanaParser
  alias TimeZoneInfo.Transformer.Rule
  alias TimeZoneInfo.Transformer.ZoneState

  @type version :: String.t()

  @doc """
  Transforms the `iana_data` into a map of type `TimeZoneInfo.data()`.
  """
  @spec transform(IanaParser.output(), version(), TimeZoneInfo.data_config()) ::
          TimeZoneInfo.data()
  def transform(iana_data, version, config) do
    iana_data = Map.merge(%{rules: [], links: [], zones: []}, iana_data)
    time_zones = zones(iana_data, config)
    rules = rules(iana_data, time_zones)
    links = links(iana_data, time_zones)

    config = [
      lookahead: Keyword.fetch!(config, :lookahead),
      files: config |> Keyword.fetch!(:files) |> List.delete("version") |> Enum.sort(),
      time_zones:
        case Keyword.fetch!(config, :time_zones) do
          :all -> :all
          list -> Enum.sort(list)
        end
    ]

    %{
      time_zones: time_zones,
      rules: rules,
      links: links,
      version: version,
      config: config
    }
  end

  # Transform IANA zone to TimeZoneInfo time-zones.
  @spec zones(IanaParser.output(), TimeZoneInfo.data_config()) ::
          %{Calendar.time_zone() => [TimeZoneInfo.transition()]}
  defp zones(iana_data, config) do
    iana_data
    |> Map.get(:zones, %{})
    |> Enum.into(%{}, fn {name, zone_states} ->
      {name, ZoneState.transform(zone_states, iana_data, config)}
    end)
  end

  # Transform rules that are required by time zones.
  # These rules are used to determine periods in the future.
  @spec rules(IanaParser.output(), %{Calendar.time_zone() => [TimeZoneInfo.transition()]}) ::
          %{TimeZoneInfo.rule_name() => [TimeZoneInfo.rule()]}
  defp rules(iana_data, time_zones) do
    used_rules = used_rules(time_zones)

    iana_data
    |> Map.get(:rules, %{})
    |> Enum.filter(fn {name, _} -> Enum.member?(used_rules, name) end)
    |> Enum.into(%{}, fn {name, rules} ->
      {name, rules |> Rule.max() |> Rule.transform()}
    end)
  end

  @doc """
  Searching for rules used by time zones.

  A rule can just emit on the head of a transition list.
  """
  @spec used_rules(%{Calendar.time_zone() => [TimeZoneInfo.transition()]}) ::
          [TimeZoneInfo.rule_name()]
  def used_rules(time_zones) do
    time_zones
    |> Enum.reduce([], fn
      {_time_zone, [{_at, {_utc_offset, _std_offset, _zone_abbr, _wall}} | _transitions]}, acc ->
        acc

      {_time_zone, [{_at, {_, rule_name, _}} | _transitions]}, acc ->
        [rule_name | acc]
    end)
    |> Enum.uniq()
  end

  # Filters out all links that refer to an existing time zone.
  @spec links(IanaParser.output(), %{Calendar.time_zone() => [TimeZoneInfo.transition()]}) ::
          %{Calendar.time_zone() => Calendar.time_zone()}
  defp links(iana_data, time_zones) do
    time_zone_names = Map.keys(time_zones)

    iana_data
    |> Map.get(:links, %{})
    |> Enum.filter(fn {_, name} ->
      Enum.member?(time_zone_names, name)
    end)
    |> Enum.into(%{})
  end
end
