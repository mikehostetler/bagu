defmodule JidokaConsumer.Support.Ticket do
  @moduledoc false

  use Ash.Resource,
    domain: JidokaConsumer.Support,
    extensions: [AshJido],
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    validate_domain_inclusion?: false

  ets do
    private?(false)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:customer_id, :string, allow_nil?: false, public?: true)
    attribute(:order_id, :string, public?: true)
    attribute(:subject, :string, allow_nil?: false, public?: true)
    attribute(:description, :string, allow_nil?: false, public?: true)
    attribute(:status, :string, allow_nil?: false, default: "open", public?: true)
    attribute(:priority, :string, allow_nil?: false, default: "normal", public?: true)
    attribute(:category, :string, allow_nil?: false, default: "general", public?: true)
    attribute(:assignee, :string, public?: true)
    attribute(:resolution, :string, public?: true)
    timestamps()
  end

  actions do
    defaults([:read])

    create :create do
      accept([
        :customer_id,
        :order_id,
        :subject,
        :description,
        :status,
        :priority,
        :category,
        :assignee
      ])
    end

    update :update do
      accept([
        :subject,
        :description,
        :status,
        :priority,
        :category,
        :assignee,
        :resolution
      ])
    end
  end

  policies do
    policy always() do
      authorize_if(actor_present())
    end
  end

  jido do
    action(:create,
      name: "create_support_ticket",
      description: "Create a support ticket for a concrete customer issue."
    )

    action(:read,
      name: "list_support_tickets",
      description: "List support tickets visible to the current support actor."
    )

    action(:update,
      name: "update_support_ticket",
      description: "Update support ticket status, priority, assignment, or resolution."
    )
  end
end
