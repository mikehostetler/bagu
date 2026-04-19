defmodule TimeZoneInfo.Transformer.ZoneState do
  @moduledoc """
  The transformer for time-zones.
  """

  alias TimeZoneInfo.GregorianSeconds
  alias TimeZoneInfo.IanaDateTime
  alias TimeZoneInfo.IanaParser

  alias TimeZoneInfo.Transformer.Abbr
  alias TimeZoneInfo.Transformer.Rule
  alias TimeZoneInfo.Transformer.RuleSet

  @end_of_time GregorianSeconds.from_naive(~N[9999-12-31 00:00:00])

  @doc """
  Transforms the `IanaPraser.zone` data in a list of `TimeZoneInfo.transition`.
  """
  @spec transform([IanaParser.zone_state()], IanaParser.output(), TimeZoneInfo.data_config()) ::
          [TimeZoneInfo.transition()]
  def transform(zone_states, data, opts) when is_list(opts) do
    rule_sets = Rule.to_rule_sets(data[:rules], Keyword.fetch!(opts, :lookahead))

    zone_states
    |> transform_zone_states(rule_sets)
    |> delete_duplicates()
    |> add_wall_period()
    |> add_max_rules(zone_states, data)
  end

  @doc """
  Returns the until datetime for the given `zone_state` and `std_offset`.
  """
  @spec until(IanaParser.zone_state(), Calendar.std_offset()) :: TimeZoneInfo.gregorian_seconds()
  def until(zone_state, std_offset) do
    case zone_state[:until] do
      nil ->
        @end_of_time

      until ->
        until
        |> IanaDateTime.to_gregorian_seconds()
        |> GregorianSeconds.to_utc(
          zone_state[:time_standard],
          zone_state[:utc_offset],
          std_offset
        )
    end
  end

  defp transform_zone_states(
         zone_states,
         rule_sets,
         since \\ 0,
         std_offset \\ 0,
         last_zone_state \\ nil,
         acc \\ []
       )

  defp transform_zone_states(
         [],
         _rule_sets,
         _since,
         _std_offset,
         _last_zone_state,
         acc
       ) do
    List.flatten(acc)
  end

  defp transform_zone_states(
         [zone_state | zone_states],
         rule_sets,
         since,
         std_offset,
         last_zone_state,
         acc
       ) do
    {result, until, last_std_offset} =
      transform_zone_state(zone_state, rule_sets, since, std_offset, last_zone_state)

    transform_zone_states(zone_states, rule_sets, until, last_std_offset, zone_state, [
      result | acc
    ])
  end

  defp transform_zone_state(zone_state, rule_sets, since, std_offset, last_zone_state) do
    transitions(
      rule_set(rule_sets, zone_state[:rules]),
      since,
      zone_state,
      utc_offset(last_zone_state),
      std_offset
    )
  end

  defp transitions(:none, since, zone_state, _std_offset, _last_zone_state) do
    utc_offset = zone_state[:utc_offset]
    std_offset = 0
    zone_abbr = Abbr.create(zone_state[:format], utc_offset)
    until = until(zone_state, std_offset)

    {
      [{since, {utc_offset, std_offset, zone_abbr}}],
      until,
      std_offset
    }
  end

  defp transitions({:std_offset, std_offset}, since, zone_state, _std_offset, _last_zone_state) do
    utc_offset = zone_state[:utc_offset]
    zone_abbr = Abbr.create(zone_state[:format], utc_offset, std_offset)
    until = until(zone_state, std_offset)

    {
      [{since, {utc_offset, std_offset, zone_abbr}}],
      until,
      std_offset
    }
  end

  defp transitions(rule_set, since, zone_state, last_utc_offset, std_offset) do
    RuleSet.transitions(rule_set, since, zone_state, last_utc_offset, std_offset)
  end

  defp utc_offset(nil), do: 0
  defp utc_offset(zone_state), do: zone_state[:utc_offset]

  defp delete_duplicates(transitions) do
    transitions
    |> Enum.reverse()
    |> Enum.reduce([], fn
      transition, [] -> [transition]
      {_, period}, [{_, period} | _] = acc -> acc
      transition, acc -> [transition | acc]
    end)
  end

  defp add_max_rules(transitions, zone_states, data) do
    zone_states
    |> max_rules(data)
    |> add_rules(transitions)
  end

  defp max_rules(zone_states, data) do
    zone_state = List.last(zone_states)
    rules = zone_state[:rules]

    case data |> rules(rules) |> Rule.max?() do
      true -> {zone_state[:utc_offset], rules, zone_state[:format]}
      false -> :no_max_rules
    end
  end

  defp add_rules(:no_max_rules, transitions), do: transitions
  defp add_rules(rules, [{at, _} | transitions]), do: [{at, rules} | transitions]

  defp rules(data, name) do
    with {:ok, name} <- rule_name(name) do
      get_in(data, [:rules, name])
    end
  end

  defp rule_set(rule_sets, name) do
    with {:ok, name} <- rule_name(name) do
      Map.fetch!(rule_sets, name)
    end
  end

  defp rule_name(nil), do: :none
  defp rule_name(value) when is_integer(value), do: {:std_offset, value}
  defp rule_name(string), do: {:ok, string}

  @spec add_wall_period(list()) :: list()
  def add_wall_period(transitions) do
    transitions
    |> Enum.reverse()
    |> add_wall_period([])
  end

  defp add_wall_period([], acc), do: acc

  defp add_wall_period([{seconds, {utc_offset, std_offset, zone_abbr}}], acc) do
    wall_period = {to_wall(seconds, utc_offset, std_offset), :max}
    [{seconds, {utc_offset, std_offset, zone_abbr, wall_period}} | acc]
  end

  defp add_wall_period([{0, {utc_offset, std_offset, zone_abbr}} | transitions], _acc) do
    {seconds_b, _info} = hd(transitions)

    wall_period = {:min, to_wall(seconds_b, utc_offset, std_offset)}
    add_wall_period(transitions, [{0, {utc_offset, std_offset, zone_abbr, wall_period}}])
  end

  defp add_wall_period(
         [{seconds_a, {utc_offset, std_offset, zone_abbr}} | transitions],
         acc
       ) do
    {seconds_b, _info} = hd(transitions)

    wall_period = {
      to_wall(seconds_a, utc_offset, std_offset),
      to_wall(seconds_b, utc_offset, std_offset)
    }

    add_wall_period(
      transitions,
      [{seconds_a, {utc_offset, std_offset, zone_abbr, wall_period}} | acc]
    )
  end

  defp to_wall(seconds, utc_offset, std_offset) do
    seconds
    |> GregorianSeconds.to_naive()
    |> NaiveDateTime.add(utc_offset + std_offset)
  end
end
