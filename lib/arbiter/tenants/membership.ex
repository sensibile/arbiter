defmodule Arbiter.Tenants.Membership do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "memberships" do
    field :source, :string
    field :effective_from, :utc_datetime
    field :effective_until, :utc_datetime

    belongs_to :tenant, Arbiter.Tenants.Tenant
    belongs_to :user, Arbiter.Tenants.User
    belongs_to :group, Arbiter.Tenants.Group

    timestamps(type: :utc_datetime)
  end

  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:source, :effective_from, :effective_until])
    |> validate_required([:source])
    |> unique_constraint([:tenant_id, :user_id, :group_id],
      name: :memberships_tenant_id_user_id_group_id_index
    )
  end
end
