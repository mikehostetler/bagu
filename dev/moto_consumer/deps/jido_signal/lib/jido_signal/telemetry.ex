defmodule Jido.Signal.Telemetry do
  @moduledoc false

  @spec execute([atom()], map(), map()) :: :ok
  def execute(event_name, measurements, metadata) do
    :telemetry.execute(event_name, measurements, metadata)
  end

  @spec attach(term(), [atom()], function(), map()) :: :ok | {:error, term()}
  def attach(handler_id, event_name, function, config) do
    :telemetry.attach(handler_id, event_name, function, config)
  end

  @spec detach(term()) :: :ok | {:error, term()}
  def detach(handler_id) do
    :telemetry.detach(handler_id)
  end
end
