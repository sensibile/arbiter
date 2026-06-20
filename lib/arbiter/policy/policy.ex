defmodule Arbiter.Policy.Policy do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "policies" do
    field :name, :string
    field :source, :string
    field :dsl, :string
    field :ast, :map, default: %{}
    field :version, :string
    field :status, :string, default: "draft"

    belongs_to :tenant, Arbiter.Tenants.Tenant

    timestamps(type: :utc_datetime)
  end

  def changeset(policy, attrs) do
    policy
    |> cast(attrs, [:name, :source, :dsl, :ast, :version, :status])
    |> validate_required([:name, :source, :dsl, :ast, :version, :status])
    |> unique_constraint([:tenant_id, :name, :version],
      name: :policies_tenant_id_name_version_index
    )
  end
end
