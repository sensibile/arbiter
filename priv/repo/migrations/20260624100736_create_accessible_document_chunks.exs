defmodule Arbiter.Repo.Migrations.CreateAccessibleDocumentChunks do
  use Ecto.Migration

  @primary_key_type :binary_id

  def change do
    create table(:accessible_document_chunks, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :tenant_id, references(:tenants, type: @primary_key_type, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: @primary_key_type, on_delete: :delete_all),
        null: false

      add :chunk_id, references(:chunks, type: @primary_key_type, on_delete: :delete_all),
        null: false

      add :document_id, references(:documents, type: @primary_key_type, on_delete: :delete_all),
        null: false

      add :user_policy_version, :string, null: false
      add :chunk_policy_version, :string, null: false
      add :chunk_deleted_at, :utc_datetime
      add :access_reason, {:array, :string}, null: false, default: []
      add :projected_at, :utc_datetime, null: false
      add :invalidated_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(
             :accessible_document_chunks,
             [:tenant_id, :user_id, :chunk_id, :user_policy_version],
             name: :accessible_document_chunks_identity_index
           )

    create index(
             :accessible_document_chunks,
             [:tenant_id, :user_id, :user_policy_version],
             name: :accessible_document_chunks_active_lookup_index,
             where: "chunk_deleted_at IS NULL AND invalidated_at IS NULL"
           )

    create index(:accessible_document_chunks, [:tenant_id, :chunk_id])
    create index(:accessible_document_chunks, [:tenant_id, :user_id, :invalidated_at])
  end
end
