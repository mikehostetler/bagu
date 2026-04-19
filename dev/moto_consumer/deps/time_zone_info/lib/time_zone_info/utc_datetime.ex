defmodule TimeZoneInfo.UtcDateTime do
  @moduledoc false

  # A behaviour to wrap DateTime.utc_now/0

  @callback now() :: DateTime.t()
  @callback now(:datetime | :unix) :: DateTime.t()

  def now(type \\ :datetime)

  def now(:datetime) do
    case Application.get_env(:time_zone_info, :utc_datetime) do
      nil -> DateTime.utc_now()
      mod -> mod.now(:datetime)
    end
  end

  def now(:unix), do: now(:datetime) |> DateTime.to_unix()
end
