defmodule TimeZoneInfo.DataStore do
  @moduledoc """
  A behaviour to store data and serve them later on.
  """

  @default_time_zone "Etc/UTC"

  @doc "Puts the given `data` into the store."
  @callback put(data :: TimeZoneInfo.data()) :: :ok | :error

  @doc """
  Returns the `transitions` for a given `time_zone`.
  """
  @callback fetch_transitions(time_zone :: Calendar.time_zone()) ::
              {:ok, transitions :: [TimeZoneInfo.transition()]} | {:error, :transitions_not_found}

  @doc """
  Returns `rules` for a given `rule_name`.
  """
  @callback fetch_rules(rule_name :: TimeZoneInfo.rule_name()) ::
              {:ok, rules :: [TimeZoneInfo.rule()]} | {:error, :rule_not_found}

  @doc """
  Returns the list of all available time zones with or without links. The option
  `:links` can be used to customize the list.

  Values for `:links`:
  - `:ignore` just the time zone names will be returned
  - `:only` just the link name will be returned
  - `:include` the time zone and link names will be returned

  The list will be sorted.
  """
  @callback get_time_zones(links: :ignore | :only | :include) :: [Calendar.time_zone()]

  @doc """
  Returns true if the `DataSore` is empty.
  """
  @callback empty? :: boolean

  @doc """
  Returns the version of the IANA database from which the data was generated.
  """
  @callback version :: String.t() | nil

  @doc """
  Deletes all data in the data store.
  """
  @callback delete! :: :ok

  @doc """
  Returns infos about the data store.
  """
  @callback info :: term()

  @optional_callbacks info: 0

  # Implementation

  defp impl do
    case Application.fetch_env!(:time_zone_info, :data_store) do
      :detect -> detect()
      module -> module
    end
  end

  defp detect do
    module =
      case function_exported?(:persistent_term, :get, 0) do
        true -> __MODULE__.PersistentTerm
        false -> __MODULE__.ErlangTermStorage
      end

    Application.put_env(:time_zone_info, :data_store, module)

    module
  end

  @doc false
  @spec fetch_transitions(Calendar.time_zone()) ::
          {:ok, [TimeZoneInfo.transition()]} | {:error, :transitions_not_found}
  def fetch_transitions(time_zone), do: impl().fetch_transitions(time_zone)

  @doc false
  @spec get_time_zones(links: :ignore | :only | :include) :: [Calendar.time_zone()]
  def get_time_zones(opts) do
    time_zones = impl().get_time_zones(opts)

    case opts[:links] do
      :only ->
        time_zones

      _else ->
        case Enum.member?(time_zones, @default_time_zone) do
          true -> time_zones
          false -> Enum.sort([@default_time_zone | time_zones])
        end
    end
  end

  @doc false
  @spec fetch_rules(TimeZoneInfo.rule_name()) ::
          {:ok, [TimeZoneInfo.rule()]} | {:error, :rules_not_found}
  def fetch_rules(rule_name), do: impl().fetch_rules(rule_name)

  @doc false
  @spec put(TimeZoneInfo.data()) :: :ok | :error
  def put(data), do: impl().put(data)

  @doc false
  @spec empty? :: boolean()
  def empty?, do: impl().empty?()

  @doc false
  @spec version :: String.t() | nil
  def version, do: impl().version()

  @doc false
  @spec delete! :: :ok
  def delete!, do: impl().delete!()

  @doc false
  @spec info :: term()
  def info do
    impl = impl()

    case function_exported?(impl, :info, 0) do
      false -> :no_implementation_found
      true -> impl.info()
    end
  end
end
