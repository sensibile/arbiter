defmodule Arbiter.ReadModels do
  @moduledoc """
  Repo boundary for runtime read model projections.

  Read models are derived storage. They speed up gateway and retrieval reads,
  but command-state tables remain the source of truth.
  """

  import Ecto.Query

  alias Arbiter.ReadModels.AccessibleDocumentChunk
  alias Arbiter.Repo

  def put_accessible_document_chunk(attrs) when is_map(attrs) do
    changeset =
      %AccessibleDocumentChunk{}
      |> AccessibleDocumentChunk.changeset(attrs)

    Repo.insert(changeset,
      on_conflict:
        {:replace,
         [
           :document_id,
           :chunk_policy_version,
           :chunk_deleted_at,
           :access_reason,
           :projected_at,
           :invalidated_at,
           :updated_at
         ]},
      conflict_target: [:tenant_id, :user_id, :chunk_id, :user_policy_version],
      returning: true
    )
  end

  def accessible_chunk_ids(%{
        tenant_id: tenant_id,
        user_id: user_id,
        user_policy_version: user_policy_version
      }) do
    AccessibleDocumentChunk
    |> where([projection], projection.tenant_id == ^tenant_id)
    |> where([projection], projection.user_id == ^user_id)
    |> where([projection], projection.user_policy_version == ^user_policy_version)
    |> where([projection], is_nil(projection.chunk_deleted_at))
    |> where([projection], is_nil(projection.invalidated_at))
    |> order_by([projection], asc: projection.chunk_id)
    |> select([projection], projection.chunk_id)
    |> Repo.all()
  end

  def accessible_chunk_ids(_invalid_scope), do: []

  def invalidate_user_access(
        tenant_id,
        user_id,
        user_policy_version,
        %DateTime{} = invalidated_at
      ) do
    {count, _rows} =
      AccessibleDocumentChunk
      |> where([projection], projection.tenant_id == ^tenant_id)
      |> where([projection], projection.user_id == ^user_id)
      |> where([projection], projection.user_policy_version == ^user_policy_version)
      |> where([projection], is_nil(projection.invalidated_at))
      |> Repo.update_all(set: [invalidated_at: invalidated_at, updated_at: invalidated_at])

    {:ok, count}
  end

  def invalidate_user_access(_tenant_id, _user_id, _user_policy_version, _invalidated_at),
    do: {:error, :invalid_invalidation_scope}
end
