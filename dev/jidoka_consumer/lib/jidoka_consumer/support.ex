defmodule JidokaConsumer.Support do
  @moduledoc false

  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource(JidokaConsumer.Support.Ticket)
  end
end
