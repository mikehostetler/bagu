defmodule TimeZoneInfo.IanaParser do
  @moduledoc """
  The IANA-Parser builds the data structure for `TimeZoneInfo`.

  The format of the IANA data explains the article [How to Read the tz Database
  Source Files](https://data.iana.org/time-zones/tz-how-to.html)
  """

  import NimbleParsec
  import TimeZoneInfo.IanaParser.Helper

  alias TimeZoneInfo.Transformer.Abbr

  @typedoc "The raw IANA data."
  @type data :: binary()

  @typedoc "The parsed data."
  @type output :: %{
          optional(:zones) => %{Calendar.time_zone() => [zone_state()]},
          optional(:rules) => %{TimeZoneInfo.rule_name() => [rule()]},
          optional(:links) => %{Calendar.time_zone() => Calendar.time_zone()}
        }

  @type rule :: [
          from: Calendar.year(),
          to: Calendar.year() | :only,
          in: Calendar.month(),
          on: day(),
          at: time(),
          time_standard: TimeZoneInfo.time_standard(),
          std_offset: Calendar.std_offset(),
          letters: String.t() | nil
        ]

  @type zone_state ::
          [
            utc_offset: Calendar.utc_offset(),
            rules: String.t() | integer() | nil,
            format: Abbr.format(),
            until: until(),
            time_standard: TimeZoneInfo.time_standard()
          ]

  @type day ::
          non_neg_integer()
          | [last_day_of_week: Calendar.day_of_week()]
          | [day: Calendar.day(), op: op(), day_of_week: Calendar.day_of_week()]

  @type time :: {Calendar.hour(), Calendar.minute(), Calendar.second()}

  @type until ::
          {Calendar.year()}
          | {Calendar.year(), Calendar.month()}
          | {Calendar.year(), Calendar.month(), day()}
          | {Calendar.year(), Calendar.month(), day(), Calendar.hour()}
          | {Calendar.year(), Calendar.month(), day(), Calendar.hour(), Calendar.minute()}
          | {Calendar.year(), Calendar.month(), day(), Calendar.hour(), Calendar.minute(),
             Calendar.second()}

  @type op :: :ge | :le

  empty_line =
    whitespace()
    |> choice([string("\n"), string("\r\n")])
    |> ignore()

  comment =
    whitespace()
    |> string("#")
    |> text()
    |> close()
    |> ignore()

  rule =
    record("Rule")
    |> whitespace()
    |> word(:name)
    |> whitespace()
    |> int(:from)
    |> whitespace()
    |> to_year()
    |> whitespace()
    |> ignore(word())
    |> whitespace()
    |> month(:in)
    |> whitespace()
    |> on(:on)
    |> whitespace()
    |> time(:at)
    |> time_standard()
    |> whitespace()
    |> seconds(:std_offset)
    |> whitespace()
    |> word(:letters)
    |> close(:rule)

  link =
    record("Link")
    |> word(:to)
    |> whitespace()
    |> word(:from)
    |> close(:link)

  zone_state =
    seperator()
    |> seconds(:utc_offset)
    |> seperator()
    |> rules()
    |> seperator()
    |> format()
    |> optional(seperator())
    |> optional(until())
    |> optional(time_standard())
    |> optional(comment)
    |> close()
    |> reduce({:zone_state, []})

  zone =
    record("Zone")
    |> word(:name)
    |> tag(times(choice([zone_state, comment]), min: 1), :states)
    |> close(:zone)

  parser =
    choice([empty_line, comment, rule, link, zone])
    |> repeat()
    |> collect()

  defparsecp :do_parse, parser

  @doc """
  Builds the data structure `IanaParser.output` from the `iana_data`.
  """
  @spec parse(data()) :: {:ok, output()} | {:error, rest, line, byte_offset}
        when rest: String.t(), line: non_neg_integer(), byte_offset: non_neg_integer()
  def parse(iana_data) when is_binary(iana_data) do
    case do_parse(iana_data) do
      {:ok, [data], "", %{}, {_line, _position}, _byte_offset} ->
        {:ok, data}

      {:ok, [_data], rest, _context, {line, _position}, byte_offset} ->
        {:error, rest, line, byte_offset}

      {:error, _reason, rest, _context, {line, _position}, byte_offset} ->
        {:error, rest, line, byte_offset}
    end
  end

  @doc """
  Builds the data structure `IanaParser.output` from the IANA data in `files`
  under `path`.
  """
  @spec parse(Path.t(), String.t()) :: {:ok, output()} | {:error, rest, line, byte_offset}
        when rest: String.t(), line: non_neg_integer(), byte_offset: non_neg_integer()
  def parse(path, files) do
    path |> read(files) |> parse()
  end

  defp read(path, files) do
    Enum.map_join(files, "\n", fn file -> path |> Path.join(file) |> File.read!() end)
  end
end
