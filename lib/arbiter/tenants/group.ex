defmodule Arbiter.Tenants.Group do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "groups" do
    field :name, :string

    belongs_to :tenant, Arbiter.Tenants.Tenant
    has_many :memberships, Arbiter.Tenants.Membership

    timestamps(type: :utc_datetime)
  end

  def changeset(group, attrs) do
    group
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> unique_constraint(:name, name: :groups_tenant_id_name_index)
  end
end
