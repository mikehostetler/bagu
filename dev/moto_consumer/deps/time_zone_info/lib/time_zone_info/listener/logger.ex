defmodule TimeZoneInfo.Listener.Logger do
  @moduledoc """
  A listener to log `TimeZoneInfo` events.
  """

  @behaviour TimeZoneInfo.Listener

  require Logger

  @impl true
  @doc false
  def on_update(:initial) do
    Logger.info("TimeZoneInfo: Initializing data.")
  end

  def on_update(:check) do
    Logger.info("TimeZoneInfo: Checking for update.")
  end

  def on_update(:config_changed) do
    Logger.info("TimeZoneInfo: Config changed.")
  end

  def on_update(:download) do
    Logger.info("TimeZoneInfo: Downloading data.")
  end

  def on_update(:update) do
    Logger.info("TimeZoneInfo: Updating data.")
  end

  def on_update(:up_to_date) do
    Logger.info("TimeZoneInfo: No update available.")
  end

  def on_update(:not_required) do
    Logger.info("TimeZoneInfo: No update required.")
  end

  def on_update(:force) do
    Logger.info("TimeZoneInfo: Force update.")
  end

  def on_update(:disabled) do
    Logger.info("TimeZoneInfo: Updating is disabled.")
  end

  def on_update({:error, _} = error) do
    Logger.error("TimeZoneInfo: Update failed! #{inspect(error)}")
  end
end
