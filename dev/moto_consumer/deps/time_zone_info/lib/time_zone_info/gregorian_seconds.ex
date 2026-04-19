defmodule TimeZoneInfo.GregorianSeconds do
  @moduledoc false

  # An implementation for gregorian seconds.

  @typep t :: TimeZoneInfo.gregorian_seconds()

  @utc [:utc, :gmt, :zulu]

  @doc """
  Converts seconds to UTC seconds.
  """
  @spec to_utc(
          t(),
          TimeZoneInfo.time_standard(),
          Calendar.utc_offset(),
          Calendar.std_offset()
        ) :: t()
  def to_utc(seconds, time_standard, _utc_offset, _std_offset) when time_standard in @utc do
    seconds
  end

  def to_utc(seconds, time_standard, utc_offset, std_offset) do
    case time_standard do
      :wall -> seconds + (utc_offset + std_offset) * -1
      :standard -> seconds + utc_offset * -1
    end
  end

  @doc """
  Computes the number of gregorian seconds starting with year 0 and ending at
  the specified `naive_datetime`.
  """
  @spec from_naive(NaiveDateTime.t()) :: t()
  def from_naive(%NaiveDateTime{calendar: Calendar.ISO, year: year}) when year < 0, do: 0

  def from_naive(%NaiveDateTime{calendar: Calendar.ISO} = naive_datetime) do
    naive_datetime
    |> NaiveDateTime.to_erl()
    |> :calendar.datetime_to_gregorian_seconds()
  end

  @doc """
  Computes the naive datetime from the specified number of gregorian seconds.
  """
  @spec to_naive(t()) :: NaiveDateTime.t()
  def to_naive(seconds) when seconds >= 0 do
    seconds
    |> :calendar.gregorian_seconds_to_datetime()
    |> NaiveDateTime.from_erl!()
  end
end
