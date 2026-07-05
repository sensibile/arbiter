defmodule Arbiter.Repo.Migrations.AddLockedByToSyncOutboxEvents do
  use Ecto.Migration

  def change do
    alter table(:sync_outbox_events) do
      add :locked_by, :string
    end
  end
end
