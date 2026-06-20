defmodule Arbiter.Tenants.Tenant do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "tenants" do
    field :name, :string
    field :isolation_level, :string, default: "tenant"
    field :policy_version, :string, default: "policy_v1"

    has_many :users, Arbiter.Tenants.User
    has_many :groups, Arbiter.Tenants.Group
    has_many :documents, Arbiter.Documents.Document
    has_many :policies, Arbiter.Policy.Policy

    timestamps(type: :utc_datetime)
  end

  def changeset(tenant, attrs) do
    tenant
    |> cast(attrs, [:name, :isolation_level, :policy_version])
    |> validate_required([:name, :isolation_level, :policy_version])
    |> unique_constraint(:name)
  end
end
