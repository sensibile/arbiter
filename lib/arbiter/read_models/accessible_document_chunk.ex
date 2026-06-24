defmodule Arbiter.ReadModels.AccessibleDocumentChunk do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "accessible_document_chunks" do
    field :user_policy_version, :string
    field :chunk_policy_version, :string
    field :chunk_deleted_at, :utc_datetime
    field :access_reason, {:array, :string}, default: []
    field :projected_at, :utc_datetime
    field :invalidated_at, :utc_datetime

    belongs_to :tenant, Arbiter.Tenants.Tenant
    belongs_to :user, Arbiter.Tenants.User
    belongs_to :chunk, Arbiter.Documents.Chunk
    belongs_to :document, Arbiter.Documents.Document

    timestamps(type: :utc_datetime)
  end

  def changeset(accessible_document_chunk, attrs) do
    accessible_document_chunk
    |> cast(attrs, [
      :tenant_id,
      :user_id,
      :chunk_id,
      :document_id,
      :user_policy_version,
      :chunk_policy_version,
      :chunk_deleted_at,
      :access_reason,
      :projected_at,
      :invalidated_at
    ])
    |> validate_required([
      :tenant_id,
      :user_id,
      :chunk_id,
      :document_id,
      :user_policy_version,
      :chunk_policy_version,
      :access_reason,
      :projected_at
    ])
    |> unique_constraint([:tenant_id, :user_id, :chunk_id, :user_policy_version],
      name: :accessible_document_chunks_identity_index
    )
  end
end
