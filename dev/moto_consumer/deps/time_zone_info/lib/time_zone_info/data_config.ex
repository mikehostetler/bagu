defmodule TimeZoneInfo.DataConfig do
  @moduledoc false

  alias TimeZoneInfo.Transformer

  @separator "/"

  @doc """
  Returns the data updated by the given time_zones.
  """
  @spec update_time_zones(TimeZoneInfo.data(), TimeZoneInfo.time_zones()) ::
          {:ok, TimeZoneInfo.data()} | {:error, {:time_zones_not_found, [String.t()]}}
  def update_time_zones(data, :all), do: {:ok, data}

  def update_time_zones(data, nil), do: {:ok, data}

  def update_time_zones(data, select_time_zones) when is_list(select_time_zones) do
    case filter(data, select_time_zones) do
      {time_zones, []} ->
        select(data, time_zones)

      {_, missing} ->
        {:error, {:time_zones_not_found, missing}}
    end
  end

  @spec equal?(TimeZoneInfo.data(), TimeZoneInfo.data_config()) :: boolean
  def equal?(data, data_config) do
    data_config = [
      lookahead: Keyword.fetch!(data_config, :lookahead),
      files: data_config |> Keyword.fetch!(:files) |> Enum.sort(),
      time_zones:
        case Keyword.fetch!(data_config, :time_zones) do
          :all -> :all
          time_zones when is_list(time_zones) -> Enum.sort(time_zones)
        end
    ]

    data
    |> Map.fetch!(:config)
    |> Keyword.equal?(data_config)
  end

  defp select(data, selected_time_zones) do
    time_zones =
      data.time_zones
      |> Enum.filter(fn {name, _} -> Enum.member?(selected_time_zones, name) end)
      |> Enum.into(%{})

    rules = rules(data, time_zones)
    links = links(data, selected_time_zones)

    {:ok, Map.merge(data, %{time_zones: time_zones, rules: rules, links: links})}
  end

  defp rules(data, time_zones) do
    used_rules = Transformer.used_rules(time_zones)

    data.rules
    |> Enum.filter(fn {name, _} -> Enum.member?(used_rules, name) end)
    |> Enum.into(%{})
  end

  defp links(data, selected_time_zones) do
    data
    |> Map.get(:links, %{})
    |> Enum.filter(fn {from, to} ->
      Enum.member?(selected_time_zones, from) && Enum.member?(selected_time_zones, to)
    end)
    |> Enum.into(%{})
  end

  defp filter(data, select) do
    links = Map.fetch!(data, :links)

    select = split(select)
    time_zones = data |> Map.fetch!(:time_zones) |> Map.keys() |> split()
    time_zone_links = links |> Map.keys() |> split()

    all_time_zones = time_zones |> Enum.concat(time_zone_links) |> Enum.uniq()

    {found, missing} =
      {[], []}
      |> filter_time_zones(all_time_zones, select)
      |> join()

    linked =
      Enum.reduce(found, [], fn time_zone, acc ->
        case Map.fetch(links, time_zone) do
          {:ok, to} -> [to | acc]
          :error -> acc
        end
      end)

    {Enum.concat(found, linked), missing}
  end

  defp filter_time_zones(acc, _time_zones, []), do: acc

  defp filter_time_zones({found, missing}, all, [time_zone | select]) do
    case time_zone_members(all, time_zone) do
      [] -> filter_time_zones({found, [time_zone | missing]}, all, select)
      time_zones -> filter_time_zones({time_zones ++ found, missing}, all, select)
    end
  end

  defp time_zone_members(time_zones, member) do
    Enum.reduce(time_zones, [], fn time_zone, acc ->
      case List.starts_with?(time_zone, member) do
        true -> [time_zone | acc]
        false -> acc
      end
    end)
  end

  defp split(list), do: Enum.map(list, fn item -> String.split(item, @separator) end)

  defp join({time_zones_found, time_zones_missing}),
    do: {join(time_zones_found), join(time_zones_missing)}

  defp join(time_zones) do
    time_zones
    |> Enum.map(fn time_zone -> Enum.join(time_zone, @separator) end)
    |> Enum.uniq()
  end
end
