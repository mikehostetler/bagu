defmodule Moto.Scripts.Demo.Hooks.NotifyInterrupt do
  use Moto.Hook, name: "notify_interrupt"

  @impl true
  def call(%Moto.Hooks.InterruptInput{interrupt: interrupt}) do
    if pid = get_in(interrupt.data, [:notify_pid]) do
      send(pid, {:demo_interrupt, interrupt})
    end

    :ok
  end
end
