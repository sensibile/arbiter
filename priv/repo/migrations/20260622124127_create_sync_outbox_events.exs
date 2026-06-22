defmodule Arbiter.Repo.Migrations.CreateSyncOutboxEvents do
  use Ecto.Migration

  @primary_key_type :binary_id

  def change do
    create table(:sync_outbox_events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :tenant_id, references(:tenants, type: @primary_key_type, on_delete: :delete_all),
        null: false

      add :event_type, :string, null: false
      add :aggregate_type, :string, null: false
      add :aggregate_id, :binary_id, null: false
      add :payload, :map, null: false, default: %{}
      add :status, :string, null: false, default: "pending"
      add :attempts, :integer, null: false, default: 0
      add :available_at, :utc_datetime, null: false
      add :locked_at, :utc_datetime
      add :processed_at, :utc_datetime
      add :last_error, :text

      timestamps(type: :utc_datetime)
    end

    create index(:sync_outbox_events, [:tenant_id])
    create index(:sync_outbox_events, [:tenant_id, :aggregate_type, :aggregate_id])
    create index(:sync_outbox_events, [:status, :available_at])
  end
end
