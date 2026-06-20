defmodule Arbiter.Documents.Document do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "documents" do
    field :source, :string
    field :department_id, :string
    field :classification, :string, default: "internal"
    field :sensitivity_level, :integer, default: 0
    field :status, :string, default: "active"
    field :acl_version, :string, default: "acl_v1"

    belongs_to :tenant, Arbiter.Tenants.Tenant
    belongs_to :owner, Arbiter.Tenants.User
    has_many :chunks, Arbiter.Documents.Chunk

    timestamps(type: :utc_datetime)
  end

  def changeset(document, attrs) do
    document
    |> cast(attrs, [
      :source,
      :department_id,
      :classification,
      :sensitivity_level,
      :status,
      :acl_version
    ])
    |> validate_required([:source, :classification, :sensitivity_level, :status, :acl_version])
    |> validate_number(:sensitivity_level, greater_than_or_equal_to: 0)
  end
end
