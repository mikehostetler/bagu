defmodule TimeZoneInfo.DataPersistence do
  @moduledoc """
  A behaviour to persist the data.
  """

  @doc """
  Persists the given data.
  """
  @callback put(TimeZoneInfo.data()) :: :ok | {:error, term()}

  @doc """
  Returns the persisted data.
  """
  @callback fetch :: {:ok, TimeZoneInfo.data()} | {:error, term()}

  @doc """
  Returns the checksum for the persisted data.
  """
  @callback checksum :: {:ok, binary()} | {:error, :no_data} | {:error, term()}

  @doc """
  Returns the timestamp of the last update in seconds since epoch.
  """
  @callback fetch_last_update :: {:ok, non_neg_integer()} | {:error, term()}

  @doc """
  Sets `time` as last update time stamp. `time` is given in seconds since epoch.
  """
  @callback put_last_update(time :: non_neg_integer()) :: :ok | {:error, term()}

  @doc """
  Returns infos about the persisted data.
  """
  @callback info :: term()

  @optional_callbacks info: 0

  # Implementation

  @spec impl :: module()
  defp impl, do: Application.fetch_env!(:time_zone_info, :data_persistence)

  @doc false
  @spec put(TimeZoneInfo.data()) :: :ok | {:error, term()}
  def put(data), do: impl().put(data)

  @doc false
  @spec fetch() :: {:ok, TimeZoneInfo.data()} | {:error, term()}
  def fetch, do: impl().fetch()

  @doc false
  @spec checksum() :: {:ok, binary()} | {:error, :no_data} | {:error, term()}
  def checksum, do: impl().checksum()

  @doc false
  @spec fetch_last_update :: {:ok, non_neg_integer()} | {:error, term()}
  def fetch_last_update, do: impl().fetch_last_update()

  @doc false
  @spec put_last_update(non_neg_integer()) :: :ok | {:error, term()}
  def put_last_update(time), do: impl().put_last_update(time)

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
