defmodule Jidoka.Kino.LoggerHandler do
  @moduledoc """
  Internal logger handler used by `Jidoka.Kino.trace/3`.

  The handler forwards formatted runtime log messages back to the Livebook cell
  process that installed it.
  """

  @doc "Accepts the logger handler configuration unchanged."
  @spec adding_handler(term()) :: {:ok, term()}
  def adding_handler(config), do: {:ok, config}

  @doc "Acknowledges removal of the temporary logger handler."
  @spec removing_handler(term()) :: :ok
  def removing_handler(_config), do: :ok

  @doc "Accepts logger handler configuration updates unchanged."
  @spec changing_config(term(), term(), term()) :: {:ok, term()}
  def changing_config(_set_or_update, _old_config, new_config), do: {:ok, new_config}

  @doc "Returns the active logger filter configuration unchanged."
  @spec filter_config(term()) :: term()
  def filter_config(config), do: config

  @doc "Forwards one logger event to the configured collector process."
  @spec log(map(), map()) :: term()
  def log(%{level: level, msg: message, meta: metadata}, %{config: %{collector: collector}}) do
    send(collector, {:jidoka_kino_log, %{level: level, message: format_message(message), metadata: metadata}})
  end

  defp format_message({:string, message}), do: to_string(message)
  defp format_message({:report, report}), do: inspect(report, pretty: true, limit: 50)

  defp format_message({:format, format, args}) do
    format
    |> :io_lib.format(args)
    |> IO.iodata_to_binary()
  rescue
    _error -> inspect({format, args}, limit: 50)
  end

  defp format_message(message), do: inspect(message, limit: 50)
end
