defmodule Arbiter.Documents.Chunk do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "chunks" do
    field :text, :string
    field :embedding_id, :string
    field :department_id, :string
    field :sensitivity_level, :integer, default: 0
    field :visibility, :string, default: "department"
    field :acl_version, :string, default: "acl_v1"
    field :policy_version, :string, default: "policy_v1"
    field :deleted_at, :utc_datetime

    belongs_to :document, Arbiter.Documents.Document
    belongs_to :tenant, Arbiter.Tenants.Tenant

    timestamps(type: :utc_datetime)
  end

  def changeset(chunk, attrs) do
    chunk
    |> cast(attrs, [
      :text,
      :embedding_id,
      :department_id,
      :sensitivity_level,
      :visibility,
      :acl_version,
      :policy_version,
      :deleted_at
    ])
    |> validate_required([:text, :sensitivity_level, :visibility, :acl_version, :policy_version])
    |> validate_number(:sensitivity_level, greater_than_or_equal_to: 0)
  end
end
