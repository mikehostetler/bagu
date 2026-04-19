defmodule Moto.Scripts.Demo.Tools.AddNumbers do
  use Moto.Tool,
    description: "Adds two integers together.",
    schema: Zoi.object(%{a: Zoi.integer(), b: Zoi.integer()})

  @impl true
  def run(%{a: a, b: b}, context) do
    sum = a + b
    tenant = Map.get(context, :tenant, Map.get(context, "tenant", "unknown"))
    channel = Map.get(context, :channel, Map.get(context, "channel", "unknown"))
    session = Map.get(context, :session, Map.get(context, "session"))

    suffix =
      case session do
        nil -> ""
        "" -> ""
        value -> " session=#{value}"
      end

    IO.puts("[tool:add_numbers tenant=#{tenant} channel=#{channel}#{suffix}] #{a} + #{b} = #{sum}")
    {:ok, %{sum: sum}}
  end
end
