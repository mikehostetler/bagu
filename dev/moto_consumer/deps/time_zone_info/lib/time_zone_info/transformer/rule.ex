defmodule TimeZoneInfo.Transformer.Rule do
  @moduledoc """
  This module handles and transforms the IANA rules.
  """

  alias TimeZoneInfo.IanaDateTime
  alias TimeZoneInfo.IanaParser
  alias TimeZoneInfo.Transformer.RuleSet
  alias TimeZoneInfo.UtcDateTime

  @doc """
  Returns a map of rule-set for the given map of `rules`.
  """
  @spec to_rule_sets(%{String.t() => [TimeZoneInfo.rule()]}, non_neg_integer()) ::
          %{String.t() => RuleSet.t()}
  def to_rule_sets(rules, lookahead) when is_integer(lookahead) do
    Enum.into(rules, %{}, fn {name, rules} ->
      {name, to_rule_set(rules, lookahead)}
    end)
  end

  @doc """
  Returns a rule-set for the given `rules`.
  """
  @spec to_rule_set([TimeZoneInfo.rule()], non_neg_integer) :: RuleSet.t()
  def to_rule_set(rules, lookahead) when is_integer(lookahead) do
    now = UtcDateTime.now()

    rule_set =
      Enum.flat_map(rules, fn rule ->
        from = rule[:from]

        to =
          case rule[:to] do
            :max -> max(now.year + lookahead, from + 1)
            :only -> rule[:from]
            year -> year
          end

        Enum.into(from..to, [], fn year ->
          at = IanaDateTime.to_gregorian_seconds(year, rule[:in], rule[:on], rule[:at])

          {at, {rule[:time_standard], rule[:std_offset], rule[:letters]}}
        end)
      end)
      |> Enum.sort_by(fn {at, _} -> at end)

    {_, first} = first_standard(rule_set)
    [{-1, first} | rule_set]
  end

  defp first_standard(rule_set) do
    Enum.find(rule_set, fn
      {_, {_, 0, _}} -> true
      _else -> false
    end)
  end

  @doc """
  Transforms a `IanaParser.rule` to a `TimeZoneInfo.rule`. If the function gets
  a list then all rules will be transformed.
  """
  @spec transform(rule | rules) :: TimeZoneInfo.rule() | [TimeZoneInfo.rule()]
        when rule: IanaParser.rule(), rules: [IanaParser.rule()]
  def transform(rule) when is_list(rule) do
    case Keyword.keyword?(rule) do
      true ->
        {
          {rule[:in], rule[:on], rule[:at]},
          rule[:time_standard],
          rule[:std_offset],
          rule[:letters]
        }

      false ->
        rule |> Enum.map(&transform/1) |> Enum.reverse()
    end
  end

  @doc """
  Returns all rules form the rule set that are for now valid until end of time.
  """
  @spec max([IanaParser.rule()]) :: [IanaParser.rule()]
  def max(rules), do: Enum.filter(rules, &max?/1)

  @doc """
  Returns `true` if `rule` is valid until end of time or one of the `rules` is valid
  until end of time.
  """
  @spec max?(rule | rules) :: boolean when rule: IanaParser.rule(), rules: [IanaParser.rule()]
  def max?(rule_or_rules) when is_list(rule_or_rules) do
    case Keyword.keyword?(rule_or_rules) do
      true -> rule_or_rules[:to] == :max
      false -> Enum.any?(rule_or_rules, &max?/1)
    end
  end

  def max?(_rule_or_rules), do: false
end
