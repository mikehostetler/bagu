defmodule TimeZoneInfo.Transformer.Abbr do
  @moduledoc """
  This module provides some functions to create time zone abbreviations.
  """

  @typedoc "The format of a `zone_abbr`."
  @type format ::
          {:string, String.t()}
          | {:template, String.t()}
          | {:choice, [String.t()]}

  @typedoc "The `letters` for the zone abbr format."
  @type letters :: String.t() | nil

  @doc """
  Creates the zone abbr.
  """
  @spec create(format(), Calendar.utc_offset(), Calendar.std_offset(), letters()) :: String.t()
  def create(format, utc_offset, std_offset \\ 0, letters \\ nil)

  def create({:string, abbr}, _utc_offset, _std_offset, _letters), do: abbr

  def create({:choice, [abbr, _]}, _utc_offset, 0, _letters), do: abbr

  def create({:choice, [_, abbr]}, _utc_offset, _std_offset, _leters), do: abbr

  def create({:template, abbr}, _utc_offset, _std_offset, letters) do
    String.replace(abbr, "%s", letters || "")
  end

  def create({:format, :z}, utc_offset, std_offset, _letters) do
    seconds = utc_offset + std_offset
    sign = if seconds >= 0, do: "+", else: "-"
    seconds = abs(seconds)
    hours = seconds |> div(3600) |> to_string() |> String.pad_leading(2, "0")
    minutes = seconds |> rem(3600) |> div(60)
    minutes = if minutes == 0, do: "", else: minutes |> to_string() |> String.pad_leading(2, "0")

    "#{sign}#{hours}#{minutes}"
  end
end
