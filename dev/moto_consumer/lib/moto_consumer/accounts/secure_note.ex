defmodule MotoConsumer.Accounts.SecureNote do
  @moduledoc false

  use Ash.Resource,
    domain: MotoConsumer.Accounts,
    extensions: [AshJido],
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    validate_domain_inclusion?: false

  ets do
    private?(true)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:title, :string, allow_nil?: false, public?: true)
    attribute(:owner_id, :string, public?: true)
    timestamps()
  end

  actions do
    defaults([:read])

    create :create do
      accept([:title, :owner_id])
    end
  end

  policies do
    policy action_type(:create) do
      authorize_if(actor_present())
    end

    policy action_type(:read) do
      authorize_if(always())
    end
  end

  jido do
    action(:create, name: "create_secure_note")
    action(:read, name: "list_secure_notes")
  end
end
