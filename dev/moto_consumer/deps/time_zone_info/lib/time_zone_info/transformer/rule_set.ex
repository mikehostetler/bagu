defmodule TimeZoneInfo.Transformer.RuleSet do
  @moduledoc """
  A rule set is a set of IANA rules with one entry per rule execution.
  """

  alias TimeZoneInfo.GregorianSeconds
  alias TimeZoneInfo.IanaParser

  alias TimeZoneInfo.Transformer.Abbr
  alias TimeZoneInfo.Transformer.ZoneState

  @type rule :: {
          TimeZoneInfo.gregorian_seconds(),
          {TimeZoneInfo.time_standard(), Calendar.std_offset(), Abbr.letters()}
        }
  @type t :: [rule()]

  @doc """
  Generates the transitions for the given `zone_state`.
  """
  @spec transitions(
          t(),
          TimeZoneInfo.gregorian_seconds(),
          IanaParser.zone_state(),
          Calendar.utc_offset(),
          Calendar.std_offset(),
          rule() | nil,
          [TimeZoneInfo.transition()]
        ) :: {
          [TimeZoneInfo.transition()],
          TimeZoneInfo.gregorian_seconds(),
          Calendar.std_offset()
        }
  def transitions(
        rule_set,
        since,
        zone_state,
        last_utc_offset,
        last_std_offset,
        last_rule \\ nil,
        acc \\ []
      )

  def transitions([], since, zone_state, _last_utc_offset, _last_std_offset, last_rule, []) do
    acc = add([], since, zone_state, last_rule)
    std_offset = std_offset(last_rule)
    until = ZoneState.until(zone_state, std_offset)
    {acc, until, std_offset}
  end

  def transitions([], _since, zone_state, _last_utc_offset, last_std_offset, _last_rule, acc) do
    until = ZoneState.until(zone_state, last_std_offset)
    {acc, until, last_std_offset}
  end

  def transitions(
        [rule | _] = rule_set,
        since,
        zone_state,
        last_utc_offset,
        last_std_offset,
        last_rule,
        acc
      ) do
    until = ZoneState.until(zone_state, last_std_offset)
    {at, _} = transition = to_utc(rule, zone_state, last_std_offset)

    at
    |> position(since, until)
    |> transitions(
      transition,
      rule_set,
      since,
      zone_state,
      last_utc_offset,
      last_std_offset,
      last_rule,
      acc
    )
  end

  defp transitions(
         :before,
         _transition,
         [rule | rule_set],
         since,
         zone_state,
         last_utc_offset,
         last_std_offset,
         _last_rule,
         acc
       ) do
    transitions(rule_set, since, zone_state, last_utc_offset, last_std_offset, rule, acc)
  end

  defp transitions(
         :start,
         {at, {std_offset, letters}},
         [rule | rule_set],
         since,
         zone_state,
         last_utc_offset,
         _last_std_offset,
         _last_rule,
         acc
       ) do
    acc = add(acc, at, zone_state, std_offset, letters)
    transitions(rule_set, since, zone_state, last_utc_offset, std_offset, rule, acc)
  end

  defp transitions(
         :inside,
         {at, {std_offset, letters}},
         [rule | rule_set],
         since,
         zone_state,
         last_utc_offset,
         _last_std_offset,
         last_rule,
         []
       ) do
    acc =
      case start?(since, at, zone_state, last_utc_offset) do
        true ->
          add([], since, zone_state, std_offset, letters)

        false ->
          {at, _} = to_utc(rule, zone_state, std_offset(last_rule))

          []
          |> add(since, zone_state, last_rule)
          |> add(at, zone_state, std_offset, letters)
      end

    transitions(rule_set, since, zone_state, last_utc_offset, std_offset, rule, acc)
  end

  defp transitions(
         :inside,
         {at, {std_offset, letters}},
         [rule | rule_set],
         since,
         zone_state,
         last_utc_offset,
         _last_std_offset,
         _last_rule,
         acc
       ) do
    acc = add(acc, at, zone_state, std_offset, letters)
    transitions(rule_set, since, zone_state, last_utc_offset, std_offset, rule, acc)
  end

  defp transitions(
         :after,
         _transition,
         _rule_set,
         since,
         zone_state,
         _last_utc_offset,
         _last_std_offset,
         last_rule,
         []
       ) do
    acc = add([], since, zone_state, last_rule)
    std_offset = std_offset(last_rule)
    until = ZoneState.until(zone_state, std_offset)
    {acc, until, std_offset}
  end

  defp transitions(
         :after,
         _transition,
         _rule_set,
         _since,
         zone_state,
         _last_utc_offset,
         last_std_offset,
         _last_rule,
         acc
       ) do
    until = ZoneState.until(zone_state, last_std_offset)
    {acc, until, last_std_offset}
  end

  @doc """
  Generates transitions for the given `rule_set`.
  """
  @spec transitions(t(), Calendar.utc_offset(), Abbr.format()) ::
          [TimeZoneInfo.transition()]
  def transitions(rule_set, utc_offset, format),
    do: transitions_seq(rule_set, utc_offset, format)

  @spec transitions_seq(
          t(),
          Calendar.utc_offset(),
          Abbr.format(),
          Calendar.std_offset(),
          [TimeZoneInfo.transition()]
        ) :: [TimeZoneInfo.transition()]
  defp transitions_seq(rule_set, utc_offset, format, last_std_offset \\ 0, acc \\ [])

  defp transitions_seq([], _utc_offset, _format, _last_std_offset, acc) do
    ZoneState.add_wall_period(acc)
  end

  defp transitions_seq([rule | rule_set], utc_offset, format, last_std_offset, acc) do
    {at, {std_offset, letters}} = to_utc(rule, utc_offset, last_std_offset)
    zone_abbr = Abbr.create(format, utc_offset, std_offset, letters)
    transition = {at, {utc_offset, std_offset, zone_abbr}}
    transitions_seq(rule_set, utc_offset, format, std_offset, [transition | acc])
  end

  defp std_offset({_at, {_, std_offset, _}}), do: std_offset

  defp start?(since, at, zone_state, last_utc_offset) do
    utc_offset_diff = zone_state[:utc_offset] - last_utc_offset
    since == at + utc_offset_diff
  end

  defp add(transitions, at, zone_state, {_at, {_, std_offset, letters}}) do
    add(transitions, at, zone_state, std_offset, letters)
  end

  defp add(transitions, at, zone_state, std_offset, letters) do
    utc_offset = zone_state[:utc_offset]
    format = zone_state[:format]
    zone_abbr = Abbr.create(format, utc_offset, std_offset, letters)
    transition = {at, {utc_offset, std_offset, zone_abbr}}
    [transition | transitions]
  end

  defp to_utc({at, {_time_standard, std_offset, letters}}, _utc_offset, _last_std_offset)
       when at < 0 do
    {at, {std_offset, letters}}
  end

  defp to_utc({at, {time_standard, std_offset, letters}}, utc_offset, last_std_offset)
       when is_integer(utc_offset) do
    at = GregorianSeconds.to_utc(at, time_standard, utc_offset, last_std_offset)
    {at, {std_offset, letters}}
  end

  defp to_utc({at, {time_standard, std_offset, letters}}, zone_state, last_std_offset) do
    utc_offset = zone_state[:utc_offset]
    at = GregorianSeconds.to_utc(at, time_standard, utc_offset, last_std_offset)
    {at, {std_offset, letters}}
  end

  defp position(at, at, _until), do: :start

  defp position(at, since, until) do
    case {at < since, at < until} do
      {_, false} -> :after
      {true, _} -> :before
      _else -> :inside
    end
  end
end
