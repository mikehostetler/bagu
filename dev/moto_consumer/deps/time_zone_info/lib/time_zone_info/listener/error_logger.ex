defmodule TimeZoneInfo.Listener.ErrorLogger do
  @moduledoc """
  A listener to log `TimeZoneInfo` errors.

  This is the default implementation of the `TimeZoneInfo.Listener`.
  """

  @behaviour TimeZoneInfo.Listener

  require Logger

  @impl true
  @doc false
  def on_update({:error, {:invalid_config, [update: value]}}) do
    """
    TimeZoneInfo: Invalid config!
    Found #{inspect(value)} for key :update, valid values are :disabled and
    :daily.
    """
    |> to_one_line()
    |> Logger.error()
  end

  def on_update({:error, {:invalid_config, path}}) do
    """
    TimeZoneInfo: Invalid config! path: #{inspect(path)}\
    """
    |> Logger.error()
  end

  def on_update({:error, _} = error) do
    Logger.error("TimeZoneInfo: Update failed! #{inspect(error)}")
  end

  def on_update(_event), do: :ok

  defp to_one_line(string), do: String.replace(string, "\n", " ")
end
