defmodule TimeZoneInfo.DataStore.ErlangTermStorage do
  @moduledoc false

  # This module implements the `TimeZoneInfo.DataStore` and stores the data with
  # [:ets](https://erlang.org/doc/man/ets.html).

  @behaviour TimeZoneInfo.DataStore

  @app :time_zone_info
  @time_zones :time_zone_info_time_zones
  @transitions :time_zone_info_transitions
  @links :time_zone_info_links
  @rules :time_zone_info_rules

  @impl true
  def put(data) do
    create_tables([@app, @time_zones, @transitions, @links, @rules])

    with true <- put(data, :version, @app),
         true <- put(data, :time_zones, @transitions),
         true <- put(data, :rules, @rules),
         true <- put(data, :links, @links),
         true <- put(data, :time_zone_names, @time_zones) do
      :ok
    else
      _error -> :error
    end
  end

  @impl true
  def delete! do
    Enum.each([@app, @time_zones, @transitions, @links, @rules], fn table ->
      case :ets.info(table) do
        :undefined -> :ok
        _info -> :ets.delete(table)
      end
    end)
  end

  @impl true
  def fetch_transitions(:error), do: {:error, :transitions_not_found}

  def fetch_transitions({:ok, time_zone}) do
    with :error <- fetch(@transitions, time_zone) do
      {:error, :transitions_not_found}
    end
  end

  def fetch_transitions(time_zone) do
    with :error <- fetch(@transitions, time_zone) do
      @links |> fetch(time_zone) |> fetch_transitions()
    end
  end

  @impl true
  def fetch_rules(rules) do
    with :error <- fetch(@rules, rules) do
      {:error, :rules_not_found}
    end
  end

  @impl true
  def get_time_zones(links: select) when select in [:ignore, :only, :include] do
    case fetch(@time_zones, select) do
      {:ok, time_zones} -> time_zones
      :error -> []
    end
  end

  @impl true
  def version do
    case fetch(@app, :version) do
      {:ok, version} -> version
      :error -> nil
    end
  end

  @impl true
  def empty? do
    case :ets.info(@app) do
      :undefined -> true
      _info -> false
    end
  end

  @impl true
  def info do
    %{
      version: version(),
      tables: info([@app, @time_zones, @transitions, @links, @rules]),
      time_zones: length(get_time_zones(links: :ignore)),
      links: length(get_time_zones(links: :only))
    }
  end

  defp info(tables) do
    Enum.into(tables, %{}, fn table ->
      case :ets.info(table) do
        :undefined ->
          {table, :undefined}

        info ->
          {table, [size: info[:size], memory: info[:memory]]}
      end
    end)
  end

  defp put(data, :version, table) do
    :ets.insert(table, {:version, Map.fetch!(data, :version)})
  end

  defp put(data, :time_zone_names, table) do
    time_zones = data |> Map.get(:time_zones) |> Map.keys() |> Enum.sort()
    links = data |> Map.get(:links) |> Map.keys() |> Enum.sort()
    all = time_zones |> Enum.concat(links) |> Enum.sort()

    with true <- :ets.insert(table, {:ignore, time_zones}),
         true <- :ets.insert(table, {:only, links}) do
      :ets.insert(table, {:include, all})
    end
  end

  defp put(data, key, table) do
    data
    |> Map.get(key, %{})
    |> Enum.all?(fn value -> :ets.insert(table, value) end)
  end

  defp fetch(table, key) do
    case :ets.match(table, {key, :"$1"}) do
      [] -> :error
      [[value]] -> {:ok, value}
    end
  end

  defp create_tables(tables), do: Enum.each(tables, &create_table/1)

  defp create_table(table) do
    case :ets.info(table) do
      :undefined -> :ets.new(table, [:named_table, :set, :public, read_concurrency: true])
      _info -> table
    end
  end
end
