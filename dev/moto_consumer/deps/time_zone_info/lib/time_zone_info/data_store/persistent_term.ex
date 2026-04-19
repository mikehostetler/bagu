defmodule TimeZoneInfo.DataStore.PersistentTerm do
  @moduledoc false

  # This module implements the `TimeZoneInfo.DataStore` and stores the data with
  # [:persistent_term](https://erlang.org/doc/man/persistent_term.html).

  @behaviour TimeZoneInfo.DataStore

  @key {:time_zone_info, :data}

  @impl true
  def put(data) do
    data = Map.merge(%{time_zones: %{}, rules: %{}, links: %{}}, data)
    :persistent_term.put(@key, data)
  end

  @impl true
  def fetch_transitions(time_zone, is_link \\ false) do
    with :error <- fetch(:time_zones, time_zone) do
      fetch_transitions_by_link(time_zone, is_link)
    end
  end

  @impl true
  def fetch_rules(rules) do
    with :error <- fetch(:rules, rules) do
      {:error, :rules_not_found}
    end
  end

  @impl true
  def get_time_zones(links: :ignore) do
    case fetch(:time_zones) do
      {:ok, time_zones} -> time_zones |> Map.keys() |> Enum.sort()
      :error -> []
    end
  end

  def get_time_zones(links: :only) do
    case fetch(:links) do
      {:ok, links} -> links |> Map.keys() |> Enum.sort()
      :error -> []
    end
  end

  def get_time_zones(links: :include) do
    with {:ok, time_zones} <- fetch(:time_zones),
         {:ok, links} <- fetch(:links) do
      Enum.sort(Map.keys(time_zones) ++ Map.keys(links))
    else
      _error -> []
    end
  end

  @impl true
  def empty?, do: :persistent_term.get(@key, nil) == nil

  @impl true
  def version, do: get(:version)

  @impl true
  def delete! do
    :persistent_term.erase(@key)
    :ok
  end

  @impl true
  def info do
    memory =
      case :persistent_term.get(@key, nil) do
        nil -> 0
        data -> data |> :erlang.term_to_binary() |> byte_size()
      end

    %{
      version: version(),
      memory: memory,
      time_zones: length(get_time_zones(links: :ignore)),
      links: length(get_time_zones(links: :only))
    }
  end

  defp get(key) do
    case :persistent_term.get(@key, :error) do
      :error -> nil
      data -> Map.get(data, key)
    end
  end

  defp fetch(key) do
    case :persistent_term.get(@key, :error) do
      :error -> :error
      data -> Map.fetch(data, key)
    end
  end

  defp fetch(key, sub_key) do
    with {:ok, map} <- fetch(key) do
      Map.fetch(map, sub_key)
    end
  end

  defp fetch_transitions_by_link(_link, true), do: {:error, :transitions_not_found}

  defp fetch_transitions_by_link(link, false) do
    case fetch(:links, link) do
      {:ok, time_zone} -> fetch_transitions(time_zone, true)
      :error -> {:error, :transitions_not_found}
    end
  end
end
