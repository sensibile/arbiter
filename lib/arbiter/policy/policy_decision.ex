defmodule Arbiter.Policy.PolicyDecision do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "policy_decisions" do
    field :action, :string
    field :resource_type, :string
    field :resource_id, :binary_id
    field :decision, :string
    field :reason, {:array, :string}, default: []
    field :policy_version, :string
    field :user_snapshot, :map, default: %{}
    field :resource_snapshot, :map, default: %{}

    belongs_to :tenant, Arbiter.Tenants.Tenant
    belongs_to :user, Arbiter.Tenants.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(policy_decision, attrs) do
    policy_decision
    |> cast(attrs, [
      :action,
      :resource_type,
      :resource_id,
      :decision,
      :reason,
      :policy_version,
      :user_snapshot,
      :resource_snapshot
    ])
    |> validate_required([
      :action,
      :resource_type,
      :decision,
      :reason,
      :policy_version,
      :user_snapshot,
      :resource_snapshot
    ])
    |> validate_inclusion(:decision, ["allow", "deny"])
  end
end
