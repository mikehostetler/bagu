defmodule JidokaConsumer.Support.Tools.LoadOrder do
  @moduledoc false

  use Jidoka.Tool,
    description: "Loads a deterministic order snapshot for a support request.",
    schema: Zoi.object(%{account_id: Zoi.string(), order_id: Zoi.string()})

  alias JidokaConsumer.Support.Data

  @impl true
  def run(%{account_id: account_id, order_id: order_id}, _context) do
    {:ok, Data.order_snapshot(account_id, order_id)}
  end
end
