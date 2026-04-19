defmodule Moto.Scripts.Demo.Tools.AddNumbers do
  use Moto.Tool,
    description: "Adds two integers together.",
    schema: Zoi.object(%{a: Zoi.integer(), b: Zoi.integer()})

  @impl true
  def run(%{a: a, b: b}, _context) do
    sum = a + b
    IO.puts("[tool:add_numbers] #{a} + #{b} = #{sum}")
    {:ok, %{sum: sum}}
  end
end
