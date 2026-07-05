defmodule Arbiter.ReadModels do
  use Boundary,
    deps: [Arbiter.Documents, Arbiter.Policy, Arbiter.Repo, Arbiter.Tenants],
    exports: [AccessibleDocumentChunk, AccessibleDocumentChunkBuilder]

  @moduledoc """
  Repo boundary for runtime read model projections.

  Read models are derived storage. They speed up gateway and retrieval reads,
  but command-state tables remain the source of truth.
  """

  import Ecto.Query

  alias Arbiter.Documents.Chunk
  alias Arbiter.Policy.Decision
  alias Arbiter.ReadModels.AccessibleDocumentChunk
  alias Arbiter.ReadModels.AccessibleDocumentChunkBuilder
  alias Arbiter.Repo
  alias Arbiter.Tenants.User

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

  def rebuild_user_access_projection(
        tenant_id,
        user_id,
        user_policy_version,
        %DateTime{} = projected_at
      ) do
    Repo.transaction(fn ->
      case load_user_projection_source(tenant_id, user_id, user_policy_version) do
        nil ->
          Repo.rollback(:user_projection_source_not_found)

        %User{} = user ->
          invalidated_count =
            invalidate_user_access_count(tenant_id, user_id, user_policy_version, projected_at)

          chunks = load_tenant_chunks(tenant_id)

          rebuild_projection_rows(
            user,
            chunks,
            user_policy_version,
            projected_at,
            invalidated_count
          )
      end
    end)
  end

  def rebuild_user_access_projection(_tenant_id, _user_id, _user_policy_version, _projected_at),
    do: {:error, :invalid_rebuild_scope}

  defp load_user_projection_source(tenant_id, user_id, user_policy_version) do
    User
    |> where([user], user.tenant_id == ^tenant_id)
    |> where([user], user.id == ^user_id)
    |> where([user], user.policy_version == ^user_policy_version)
    |> Repo.one()
  end

  defp load_tenant_chunks(tenant_id) do
    Chunk
    |> where([chunk], chunk.tenant_id == ^tenant_id)
    |> order_by([chunk], asc: chunk.id)
    |> Repo.all()
  end

  defp invalidate_user_access_count(tenant_id, user_id, user_policy_version, invalidated_at) do
    {:ok, count} = invalidate_user_access(tenant_id, user_id, user_policy_version, invalidated_at)
    count
  end

  defp rebuild_projection_rows(user, chunks, user_policy_version, projected_at, invalidated_count) do
    if user.status != "active" do
      inactive_rebuild_result(chunks, invalidated_count)
    else
      do_rebuild_projection_rows(
        user,
        chunks,
        user_policy_version,
        projected_at,
        invalidated_count
      )
    end
  end

  defp do_rebuild_projection_rows(
         user,
         chunks,
         user_policy_version,
         projected_at,
         invalidated_count
       ) do
    decision = projection_decision(user, user_policy_version)

    rebuild_result =
      Enum.reduce_while(chunks, empty_rebuild_result(invalidated_count), fn chunk, result ->
        case AccessibleDocumentChunkBuilder.build(user, chunk, decision, projected_at) do
          {:ok, attrs} ->
            case put_accessible_document_chunk(attrs) do
              {:ok, _projection} -> {:cont, %{result | projected: result.projected + 1}}
              {:error, _changeset} -> {:halt, {:error, :projection_write_failed}}
            end

          {:error, reason} ->
            {:cont, skip_rebuild_result(result, reason)}
        end
      end)

    case rebuild_result do
      {:error, reason} ->
        Repo.rollback(reason)

      result ->
        Map.put(result, :skipped, Enum.sum(Map.values(result.skipped_reasons)))
    end
  end

  defp inactive_rebuild_result(chunks, invalidated_count) do
    skipped = length(chunks)

    %{
      projected: 0,
      skipped: skipped,
      invalidated: invalidated_count,
      skipped_reasons: %{inactive_user: skipped}
    }
  end

  defp empty_rebuild_result(invalidated_count) do
    %{
      projected: 0,
      skipped: 0,
      invalidated: invalidated_count,
      skipped_reasons: %{}
    }
  end

  defp skip_rebuild_result(result, reason) do
    update_in(result.skipped_reasons, &Map.update(&1, reason, 1, fn count -> count + 1 end))
  end

  defp projection_decision(%User{} = user, user_policy_version) do
    %Decision{
      decision: :allow,
      reason: ["same_tenant", "active_user", "clearance_ok", "department_scope_matched"],
      policy_version: user_policy_version,
      scope: %{
        "tenant_id" => user.tenant_id,
        "departments" => user.department_ids,
        "max_sensitivity" => user.clearance_level
      }
    }
  end
end
