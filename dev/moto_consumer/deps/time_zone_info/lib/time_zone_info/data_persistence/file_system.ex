defmodule TimeZoneInfo.DataPersistence.FileSystem do
  @moduledoc """
  An implementation for the behaviour `TimeZoneInfo.DataPersistence` to persist
  data in the file system.
  """

  @behaviour TimeZoneInfo.DataPersistence

  alias File.Stat
  alias TimeZoneInfo.ExternalTermFormat

  @impl true
  def put(data) do
    with {:ok, path} <- fetch_env(:path),
         {:ok, data} <- ExternalTermFormat.encode(data) do
      File.write(path, data)
    end
  end

  @impl true
  def fetch do
    with {:ok, path} <- fetch_env(:path),
         {:ok, data} <- File.read(path) do
      ExternalTermFormat.decode(data)
    end
  end

  @impl true
  def checksum do
    with {:ok, path} <- fetch_env(:path),
         {:ok, data} <- File.read(path) do
      ExternalTermFormat.checksum(data)
    end
  end

  @impl true
  def fetch_last_update do
    with {:ok, path} <- fetch_env(:path),
         {:ok, %Stat{mtime: mtime}} <- File.stat(path, time: :posix) do
      {:ok, mtime}
    end
  end

  @impl true
  def put_last_update(time) do
    with {:ok, path} <- fetch_env(:path) do
      case File.exists?(path) do
        true -> File.touch(path, time)
        false -> {:error, :enoent}
      end
    end
  end

  @impl true
  def info do
    with {:ok, path} <- fetch_env(:path),
         {:ok, stat} <- File.stat(path),
         {:ok, data} <- File.read(path) do
      %{
        stat: stat,
        path: path,
        checksum: ExternalTermFormat.checksum(data)
      }
    end
  end

  @spec fetch_env(atom()) ::
          {:ok, Path.t()} | {:error, {:invalid_config, Keyword.key() | [Keyword.key()]}}
  defp fetch_env(:path) do
    with {:ok, file_system} <- fetch_env(:file_system) do
      case Keyword.fetch(file_system, :path) do
        {:ok, path} when is_binary(path) -> {:ok, path}
        {:ok, path} -> {:error, {:invalid_config, [file_system: [path: path]]}}
        :error -> {:error, {:invalid_config, [:file_system, :path]}}
      end
    end
  end

  defp fetch_env(:file_system) do
    with :error <- Application.fetch_env(:time_zone_info, :file_system) do
      {:error, {:invalid_config, :file_system}}
    end
  end
end
