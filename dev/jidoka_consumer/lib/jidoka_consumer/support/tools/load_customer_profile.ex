defmodule JidokaConsumer.Support.Tools.LoadCustomerProfile do
  @moduledoc false

  use Jidoka.Tool,
    description: "Loads a deterministic support customer profile.",
    schema: Zoi.object(%{account_id: Zoi.string()})

  alias JidokaConsumer.Support.Data

  @impl true
  def run(%{account_id: account_id}, _context) do
    {:ok, Data.customer_profile(account_id)}
  end
end
