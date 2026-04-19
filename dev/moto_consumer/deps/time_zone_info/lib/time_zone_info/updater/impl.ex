defmodule TimeZoneInfo.Updater.Impl do
  @moduledoc false

  # Handles the automatic update and the initial setup.

  @behaviour TimeZoneInfo.Updater

  alias TimeZoneInfo.DataConfig
  alias TimeZoneInfo.DataPersistence
  alias TimeZoneInfo.DataStore
  alias TimeZoneInfo.Downloader
  alias TimeZoneInfo.ExternalTermFormat
  alias TimeZoneInfo.FileArchive
  alias TimeZoneInfo.IanaParser
  alias TimeZoneInfo.Listener
  alias TimeZoneInfo.Transformer
  alias TimeZoneInfo.UtcDateTime

  @type step ::
          :run
          | :initial
          | :force
          | :check
          | :disabled
          | :finally
          | :maybe

  @seconds_per_day 24 * 60 * 60
  @default_lookahead 5

  @doc """
  Updates the TimeZoneInfo data.

  With `opt` `:run` an normal update process is started. The `opt` `:force`
  forced an update process.

  Returns
  - `:ok` if automatic updates are disabled.
  - `{:next, seconds}` where `seconds` is the time to wait until the next update.
  - `{:error, reason}` in case of an error.
  """
  @spec update(opt :: :run | :force) :: :ok | {:next, Calendar.second()} | {:error, term()}
  def update(step \\ :run) when step in [:run, :force] do
    with {:error, _} = error <- step |> step() |> do_update() do
      Listener.on_update(error)
      error
    end
  end

  defp step(:run) do
    case DataStore.empty?() do
      true -> :initial
      false -> :check
    end
  end

  defp step(step), do: step

  defp do_update(:initial) do
    Listener.on_update(:initial)

    with {:ok, data} <- DataPersistence.fetch(),
         {:ok, data_config} <- fetch_data_config(),
         {:ok, data} <- DataConfig.update_time_zones(data, data_config[:time_zones]) do
      do_update({:initial, data, DataConfig.equal?(data, data_config)})
    else
      {:error, {:time_zones_not_found, _}} = error ->
        force_update(error)

      {:error, :enoent} = error ->
        force_update(error)

      error ->
        error
    end
  end

  defp do_update({:initial, data, true}) do
    with :ok <- DataStore.put(data) do
      do_update(:check)
    end
  end

  defp do_update({:initial, data, false}) do
    Listener.on_update(:config_changed)

    with :disabled <- force_update(:disabled) do
      DataStore.put(data)
    end
  end

  defp do_update(:force), do: force_update(:ok)

  defp do_update(:check) do
    Listener.on_update(:check)

    with {:ok, interval} <- fetch_env(:update), do: do_update(interval)
  end

  defp do_update(:disabled), do: :ok

  defp do_update(:daily) do
    with {:ok, last_update} <- DataPersistence.fetch_last_update() do
      now = UtcDateTime.now(:unix)

      case last_update + @seconds_per_day - now do
        next when next > 0 ->
          Listener.on_update(:not_required)
          {:next, now + next}

        _next ->
          with :ok <- do_update(:maybe),
               :ok <- DataPersistence.put_last_update(now) do
            {:next, now + @seconds_per_day}
          end
      end
    end
  end

  defp do_update(:maybe) do
    with {:ok, checksum_persistence} <- DataPersistence.checksum(),
         {:ok, data} when not is_atom(data) <- download(),
         {:ok, checksum_download} <- ExternalTermFormat.checksum(data) do
      case checksum_persistence == checksum_download do
        true ->
          Listener.on_update(:up_to_date)
          :ok

        false ->
          do_update(:finally, data)
      end
    else
      {:ok, :not_modified} ->
        Listener.on_update(:up_to_date)
        :ok

      error ->
        error
    end
  end

  defp do_update(:finally, data) do
    Listener.on_update(:update)

    with {:ok, time_zones} <- fetch_env(:time_zones),
         {:ok, data} <- DataConfig.update_time_zones(data, time_zones),
         :ok <- DataStore.put(data) do
      DataPersistence.put(data)
    end
  end

  defp force_update(on_disabled) do
    Listener.on_update(:force)

    now = UtcDateTime.now(:unix)

    with {:ok, update} when update != :disabled <- fetch_env(:update),
         {:ok, data} when not is_atom(data) <- download(),
         :ok <- do_update(:finally, data) do
      {:next, now + @seconds_per_day}
    else
      {:ok, :not_modified} ->
        up_to_date(now)

      {:ok, :disabled} ->
        Listener.on_update(:disabled)
        on_disabled

      error ->
        error
    end
  end

  defp up_to_date(timestamp) do
    with :ok <- DataPersistence.put_last_update(timestamp) do
      Listener.on_update(:up_to_date)
      {:next, timestamp + @seconds_per_day}
    end
  end

  defp download do
    Listener.on_update(:download)

    with {:ok, files} <- files(),
         {:ok, time_zones} <- fetch_env(:time_zones),
         {:ok, lookahead} <- fetch_env(:lookahead) do
      opts = [files: files, time_zones: time_zones, lookahead: lookahead]

      opts =
        case DataPersistence.checksum() do
          {:ok, checksum} -> Keyword.put(opts, :checksum, checksum)
          _error -> opts
        end

      case Downloader.download(opts) do
        {:ok, :iana, {200, data}} ->
          transform(data, opts)

        {:ok, mode, {200, data}} when mode in [:etf, :ws] ->
          ExternalTermFormat.decode(data)

        {:ok, _mode, {304, _body}} ->
          {:ok, :not_modified}

        {:ok, _mode, response} ->
          {:error, response}

        error ->
          error
      end
    end
  end

  defp transform(data, opts) do
    with {:ok, version, content} <- extract(data),
         {:ok, parsed} <- IanaParser.parse(content) do
      {:ok, Transformer.transform(parsed, version, opts)}
    end
  end

  defp extract(data) do
    with {:ok, files} <- files(),
         {:ok, contents} <- FileArchive.extract(data, files) do
      {version, contents} = Map.pop(contents, "version")
      {:ok, String.trim(version), join(contents)}
    end
  end

  defp join(files) do
    Enum.map_join(files, "\n", fn {_name, content} -> content end)
  end

  defp files do
    with {:ok, files} <- fetch_env(:files) do
      {:ok, ["version" | files]}
    end
  end

  defp fetch_data_config do
    with {:ok, time_zones} <- fetch_env(:time_zones),
         {:ok, lookahead} <- fetch_env(:lookahead),
         {:ok, files} <- fetch_env(:files) do
      {:ok, [time_zones: time_zones, lookahead: lookahead, files: files]}
    end
  end

  defp fetch_env(:files) do
    with :error <- Application.fetch_env(:time_zone_info, :files) do
      {:error, {:invalid_config, :files}}
    end
  end

  defp fetch_env(:update) do
    case Application.fetch_env(:time_zone_info, :update) do
      {:ok, value} when value in [:disabled, :daily] ->
        {:ok, value}

      {:ok, value} ->
        {:error, {:invalid_config, [update: value]}}

      :error ->
        {:error, {:invalid_config, :update}}
    end
  end

  defp fetch_env(:lookahead) do
    case Application.get_env(:time_zone_info, :lookahead, @default_lookahead) do
      value when value > 0 ->
        {:ok, value}

      value ->
        {:error, {:invalid_config, [lookahead: value]}}
    end
  end

  defp fetch_env(:time_zones) do
    case Application.get_env(:time_zone_info, :time_zones, :all) do
      :all ->
        {:ok, :all}

      [] ->
        {:error, {:invalid_config, [time_zones: []]}}

      [_ | _] = list ->
        validate_time_zones(list)

      value ->
        {:error, {:invalid_config, [time_zones: value]}}
    end
  end

  defp validate_time_zones(list) do
    case Enum.all?(list, fn item -> is_binary(item) end) do
      true -> {:ok, list}
      false -> {:error, {:invalid_config, [time_zones: list]}}
    end
  end
end
