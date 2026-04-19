defmodule TimeZoneInfo.IanaDateTime do
  @moduledoc false

  # Some functions to handle datetimes in `TimeZoneInfo`.

  alias Calendar.ISO

  alias TimeZoneInfo.IanaParser

  @type time :: {Calendar.hour(), Calendar.minute(), Calendar.second()}

  @type t ::
          {Calendar.year()}
          | {Calendar.year(), Calendar.month()}
          | {Calendar.year(), Calendar.month(), IanaParser.day()}
          | {Calendar.year(), Calendar.month(), IanaParser.day(), time()}

  @seconds_per_minute 60
  @seconds_per_hour 60 * @seconds_per_minute
  @seconds_per_day 24 * @seconds_per_hour

  @doc """
  Computes the number of gregorian seconds starting with year 0 and ending at
  the specified `iana_datetime`.
  """
  @spec to_gregorian_seconds(t()) :: TimeZoneInfo.gregorian_seconds()
  def to_gregorian_seconds(iana_datetime) do
    case iana_datetime do
      {year} ->
        to_gregorian_seconds(year, 1, 1, {0, 0, 0})

      {year, month} ->
        to_gregorian_seconds(year, month, 1, {0, 0, 0})

      {year, month, day} ->
        to_gregorian_seconds(year, month, day, {0, 0, 0})

      {year, month, day, hour} ->
        to_gregorian_seconds(year, month, day, {hour, 0, 0})

      {year, month, day, hour, minute} ->
        to_gregorian_seconds(year, month, day, {hour, minute, 0})

      {year, month, day, hour, minute, second} ->
        to_gregorian_seconds(year, month, day, {hour, minute, second})
    end
  end

  @spec to_gregorian_seconds(Calendar.year(), Calendar.month(), IanaParser.day(), time()) ::
          TimeZoneInfo.gregorian_seconds()
  def to_gregorian_seconds(year, month, day, time) do
    day = to_day(year, month, day)

    do_to_gregorian_seconds({{year, month, day}, time})
  end

  defp do_to_gregorian_seconds({date, time}) do
    date = update(date)
    :calendar.datetime_to_gregorian_seconds({date, time})
  end

  defp update({year, month, day}) do
    case day > 0 && day <= ISO.days_in_month(year, month) do
      true ->
        {year, month, day}

      false ->
        {:ok, date} = NaiveDateTime.new(year, month, 1, 0, 0, 0)
        date = NaiveDateTime.add(date, (day - 1) * @seconds_per_day)

        {date.year, date.month, date.day}
    end
  end

  defp to_day(_year, _month, day) when is_integer(day), do: day

  defp to_day(year, month, last_day_of_week: last_day_of_week),
    do: to_last_day_of_week(year, month, last_day_of_week)

  defp to_day(year, month, day: day, op: op, day_of_week: day_of_week),
    do: to_day_of_week(year, month, day, day_of_week, op)

  defp to_last_day_of_week(year, month, day_of_week) do
    days_in_month = ISO.days_in_month(year, month)
    {last, _first_day_of_week, _last_day_of_week} = ISO.day_of_week(year, month + 1, 1, :default)

    days_in_month - rem(7 - (day_of_week - (last - 1)), 7)
  end

  defp to_day_of_week(year, month, day, day_of_week, op) do
    {current, _first_day_of_week, _last_day_of_week} = ISO.day_of_week(year, month, day, :default)

    case op do
      :ge -> day + rem(7 + (day_of_week - current), 7)
      :le -> day - rem(7 + (current - day_of_week), 7)
    end
  end
end
