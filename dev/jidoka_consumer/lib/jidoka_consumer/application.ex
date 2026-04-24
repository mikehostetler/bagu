defmodule JidokaConsumer.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Task.Supervisor, name: JidokaConsumer.AgentViewTaskSupervisor},
      {Phoenix.PubSub, name: JidokaConsumer.PubSub},
      JidokaConsumerWeb.Endpoint
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: JidokaConsumer.Supervisor)
  end
end
