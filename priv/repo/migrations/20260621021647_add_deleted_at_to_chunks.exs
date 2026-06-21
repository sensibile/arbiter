defmodule Arbiter.Repo.Migrations.AddDeletedAtToChunks do
  use Ecto.Migration

  def change do
    alter table(:chunks) do
      add :deleted_at, :utc_datetime
    end

    create index(:chunks, [:tenant_id, :deleted_at])
  end
end
