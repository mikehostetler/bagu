defmodule TimeZoneInfo.Listener do
  @moduledoc """
  A `behaviour` for `TimeZoneInfo` listeners.
  """

  @doc """
  A callback to listen on the update process.

  Possible events:
  - `:initial` initializing data.
  - `:check` checking whether an update is necessary.
  - `:force` an update is forced.
  - `:download` downloads data.
  - `:update` updating data.
  - `:disabled` updating data is disabled.
  - `{:error, reason}`
  """
  @callback on_update(step :: atom() | {:error, term()}) :: :ok | :undefined

  defp impl do
    case Application.get_env(:time_zone_info, :listener) do
      module when is_atom(module) and module != nil -> {:ok, module}
      _undefined -> :undefined
    end
  end

  @doc false
  @spec on_update(step :: atom() | {:error, term()}) :: :ok | :undefined
  def on_update(step) do
    with {:ok, module} <- impl() do
      module.on_update(step)
    end
  end
end
