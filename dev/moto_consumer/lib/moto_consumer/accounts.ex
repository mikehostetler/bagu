defmodule MotoConsumer.Accounts do
  @moduledoc false

  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource(MotoConsumer.Accounts.SecureNote)
  end
end
