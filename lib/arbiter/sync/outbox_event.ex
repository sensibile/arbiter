defmodule Arbiter.Sync.OutboxEvent do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "sync_outbox_events" do
    field :event_type, :string
    field :aggregate_type, :string
    field :aggregate_id, :binary_id
    field :payload, :map, default: %{}
    field :status, :string, default: "pending"
    field :attempts, :integer, default: 0
    field :available_at, :utc_datetime
    field :locked_at, :utc_datetime
    field :processed_at, :utc_datetime
    field :last_error, :string

    belongs_to :tenant, Arbiter.Tenants.Tenant

    timestamps(type: :utc_datetime)
  end

  def changeset(outbox_event, attrs) do
    outbox_event
    |> cast(attrs, [
      :tenant_id,
      :event_type,
      :aggregate_type,
      :aggregate_id,
      :payload,
      :status,
      :attempts,
      :available_at,
      :locked_at,
      :processed_at,
      :last_error
    ])
    |> validate_required([
      :tenant_id,
      :event_type,
      :aggregate_type,
      :aggregate_id,
      :payload,
      :status,
      :attempts,
      :available_at
    ])
    |> validate_inclusion(:status, ["pending", "processing", "processed", "failed"])
    |> validate_number(:attempts, greater_than_or_equal_to: 0)
  end
end
