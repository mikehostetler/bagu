defmodule TimeZoneInfo.DataPersistence.Priv do
  @moduledoc """
  An implementation for the behaviour `TimeZoneInfo.DataPersistence` to persist
  data in the `priv` dir.
  """

  @behaviour TimeZoneInfo.DataPersistence

  alias TimeZoneInfo.ExternalTermFormat

  @impl true
  def put(data) do
    with {:ok, path} <- fetch_path(:data),
         {:ok, data} <- ExternalTermFormat.encode(data) do
      File.write(path, data)
    end
  end

  @impl true
  def fetch do
    with {:ok, path} <- fetch_path(:data),
         {:ok, data} <- File.read(path) do
      ExternalTermFormat.decode(data)
    end
  end

  @impl true
  def checksum do
    with {:ok, path} <- fetch_path(:data),
         {:ok, data} <- File.read(path) do
      ExternalTermFormat.checksum(data)
    end
  end

  @impl true
  def fetch_last_update do
    with {:ok, path} <- fetch_path(:timestamp),
         {:ok, string} <- File.read(path) do
      timestamp = string |> String.trim() |> String.to_integer()
      {:ok, timestamp}
    end
  end

  @impl true
  def put_last_update(timestamp) do
    with {:ok, path} <- fetch_path(:timestamp) do
      case File.exists?(path) do
        true -> File.write!(path, to_string(timestamp))
        false -> {:error, :enoent}
      end
    end
  end

  @impl true
  def info do
    with {:ok, path} <- fetch_path(:data),
         {:ok, stat} <- File.stat(path),
         {:ok, data} <- File.read(path) do
      %{
        stat: stat,
        path: path,
        checksum: ExternalTermFormat.checksum(data)
      }
    end
  end

  defp fetch_path(key) do
    with {:ok, path} <- fetch_env(key) do
      path =
        :time_zone_info
        |> :code.priv_dir()
        |> Path.join(path)

      {:ok, path}
    end
  end

  defp fetch_env(key) do
    with {:ok, priv} <- fetch_env_priv() do
      case Keyword.fetch(priv, key) do
        {:ok, value} when is_binary(value) -> {:ok, value}
        {:ok, value} -> {:error, {:invalid_config, [priv: [{key, value}]]}}
        :error -> {:error, {:invalid_config, [:priv, key]}}
      end
    end
  end

  defp fetch_env_priv do
    with :error <- Application.fetch_env(:time_zone_info, :priv) do
      {:error, {:invalid_config, :priv}}
    end
  end
end
