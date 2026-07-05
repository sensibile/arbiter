defmodule Arbiter.Sync.OutboxEvent do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @status_pending "pending"
  @status_processing "processing"
  @status_processed "processed"
  @status_failed "failed"
  @statuses [@status_pending, @status_processing, @status_processed, @status_failed]
  @terminal_statuses [@status_processed, @status_failed]

  schema "sync_outbox_events" do
    field :event_type, :string
    field :aggregate_type, :string
    field :aggregate_id, :binary_id
    field :payload, :map, default: %{}
    field :status, :string, default: @status_pending
    field :attempts, :integer, default: 0
    field :available_at, :utc_datetime
    field :locked_at, :utc_datetime
    field :locked_by, :string
    field :processed_at, :utc_datetime
    field :last_error, :string

    belongs_to :tenant, Arbiter.Tenants.Tenant

    timestamps(type: :utc_datetime)
  end

  def status_pending, do: @status_pending
  def status_processing, do: @status_processing
  def status_processed, do: @status_processed
  def status_failed, do: @status_failed
  def statuses, do: @statuses
  def terminal_statuses, do: @terminal_statuses

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
      :locked_by,
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
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:attempts, greater_than_or_equal_to: 0)
  end
end
