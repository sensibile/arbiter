defmodule Arbiter.Tenants.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "users" do
    field :email, :string
    field :status, :string, default: "active"
    field :role, :string
    field :department_ids, {:array, :string}, default: []
    field :clearance_level, :integer, default: 0
    field :policy_version, :string, default: "policy_v1"

    belongs_to :tenant, Arbiter.Tenants.Tenant
    has_many :memberships, Arbiter.Tenants.Membership
    has_many :agent_runs, Arbiter.Agents.AgentRun
    has_many :policy_decisions, Arbiter.Policy.PolicyDecision

    timestamps(type: :utc_datetime)
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :status, :role, :department_ids, :clearance_level, :policy_version])
    |> validate_required([
      :email,
      :status,
      :role,
      :department_ids,
      :clearance_level,
      :policy_version
    ])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/)
    |> validate_number(:clearance_level, greater_than_or_equal_to: 0)
    |> unique_constraint(:email, name: :users_tenant_id_email_index)
  end
end
