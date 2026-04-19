defmodule MotoTest.Support.Accounts do
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource(MotoTest.Support.User)
  end
end

defmodule MotoTest.Support.User do
  use Ash.Resource,
    domain: MotoTest.Support.Accounts,
    extensions: [AshJido],
    validate_domain_inclusion?: false

  attributes do
    uuid_primary_key(:id)
    attribute(:name, :string)
  end

  actions do
    default_accept([:name])
    create(:create)
    read(:read)
  end

  jido do
    action(:create)
    action(:read)
  end
end
