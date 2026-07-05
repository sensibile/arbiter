defmodule Arbiter.ReadModels.AccessibleDocumentChunkTest do
  use Arbiter.DataCase, async: false

  alias Arbiter.Policy.Decision
  alias Arbiter.ReadModels
  alias Arbiter.ReadModels.AccessibleDocumentChunk
  alias Arbiter.ReadModels.AccessibleDocumentChunkBuilder
  alias Arbiter.Repo

  import Arbiter.DomainFixtures

  @now ~U[2026-06-24 10:00:00Z]

  setup_all do
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)
    Ecto.Migrator.run(Repo, :up, all: true)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :manual)
    :ok
  end

  describe "accessible_document_chunks read model" do
    test "returns only active rows for the same tenant, user, and policy version" do
      %{tenant: tenant, user: user, document: document, chunk: chunk} =
        fixture_scope(policy_version: "policy_v7")

      %{tenant: other_tenant, user: other_user, document: other_document, chunk: other_chunk} =
        fixture_scope(policy_version: "policy_v7")

      deleted_chunk = chunk_fixture(tenant, document, deleted_at: @now)
      old_policy_chunk = chunk_fixture(tenant, document, policy_version: "policy_v6")

      assert {:ok, _projection} =
               put_projection(tenant, user, document, chunk,
                 user_policy_version: "policy_v7",
                 projected_at: @now
               )

      assert {:ok, _deleted_projection} =
               put_projection(tenant, user, document, deleted_chunk,
                 user_policy_version: "policy_v7",
                 projected_at: @now
               )

      assert {:ok, _old_policy_projection} =
               put_projection(tenant, user, document, old_policy_chunk,
                 user_policy_version: "policy_v6",
                 projected_at: @now
               )

      assert {:ok, _other_tenant_projection} =
               put_projection(other_tenant, other_user, other_document, other_chunk,
                 user_policy_version: "policy_v7",
                 projected_at: @now
               )

      assert active_chunk_ids(tenant, user, "policy_v7") == [chunk.id]
    end

    test "revoke invalidation removes old user policy projections from active lookup" do
      %{tenant: tenant, user: user, document: document, chunk: chunk} =
        fixture_scope(policy_version: "policy_v12")

      assert {:ok, projection} =
               put_projection(tenant, user, document, chunk,
                 user_policy_version: "policy_v12",
                 projected_at: @now
               )

      assert active_chunk_ids(tenant, user, "policy_v12") == [chunk.id]

      assert {:ok, 1} =
               ReadModels.invalidate_user_access(tenant.id, user.id, "policy_v12", @now)

      assert active_chunk_ids(tenant, user, "policy_v12") == []

      assert Repo.get!(AccessibleDocumentChunk, projection.id).invalidated_at == @now
    end

    test "upsert refreshes a stale projection row for the same identity" do
      %{tenant: tenant, user: user, document: document, chunk: chunk} =
        fixture_scope(policy_version: "policy_v3")

      assert {:ok, first_projection} =
               put_projection(tenant, user, document, chunk,
                 user_policy_version: "policy_v3",
                 projected_at: @now,
                 invalidated_at: @now
               )

      refreshed_at = DateTime.add(@now, 60, :second)

      assert {:ok, refreshed_projection} =
               put_projection(tenant, user, document, chunk,
                 user_policy_version: "policy_v3",
                 projected_at: refreshed_at,
                 invalidated_at: nil,
                 access_reason: ["department_match", "clearance_ok"]
               )

      assert refreshed_projection.id == first_projection.id
      assert refreshed_projection.invalidated_at == nil
      assert refreshed_projection.access_reason == ["department_match", "clearance_ok"]

      assert active_chunk_ids(tenant, user, "policy_v3") == [chunk.id]
    end

    test "persists attrs produced by the pure projection builder" do
      %{tenant: tenant, user: user, chunk: chunk} = fixture_scope(policy_version: "policy_v8")

      assert {:ok, projection} =
               build_and_put_projection(tenant, user, chunk,
                 user_policy_version: "policy_v8",
                 projected_at: @now,
                 access_reason: ["department_match", "clearance_ok"]
               )

      assert projection.access_reason == ["department_match", "clearance_ok"]
      assert active_chunk_ids(tenant, user, "policy_v8") == [chunk.id]
    end

    test "fails closed for malformed lookup and invalidation scopes" do
      assert ReadModels.accessible_chunk_ids(%{}) == []
      assert ReadModels.accessible_chunk_ids(%{tenant_id: Ecto.UUID.generate()}) == []

      assert ReadModels.invalidate_user_access(
               Ecto.UUID.generate(),
               Ecto.UUID.generate(),
               "policy_v1",
               "not-a-datetime"
             ) == {:error, :invalid_invalidation_scope}
    end

    test "rebuilds user access projections from current tenant chunks" do
      %{tenant: tenant, user: user, document: document, chunk: allowed_chunk} =
        fixture_scope(policy_version: "policy_v14")

      high_sensitivity_chunk =
        chunk_fixture(tenant, document, policy_version: "policy_v14", sensitivity_level: 9)

      deleted_chunk =
        chunk_fixture(tenant, document, policy_version: "policy_v14", deleted_at: @now)

      sales_chunk =
        chunk_fixture(tenant, document, policy_version: "policy_v14", department_id: "sales")

      stale_policy_chunk = chunk_fixture(tenant, document, policy_version: "policy_v13")
      %{tenant: other_tenant, document: other_document} = fixture_scope(policy_version: "policy_v14")
      _other_tenant_chunk = chunk_fixture(other_tenant, other_document, policy_version: "policy_v14")

      assert {:ok, stale_projection} =
               put_projection(tenant, user, document, high_sensitivity_chunk,
                 user_policy_version: "policy_v14",
                 projected_at: @now
               )

      assert {:ok,
              %{
                projected: 1,
                skipped: 4,
                invalidated: 1,
                skipped_reasons: %{
                  outside_sensitivity_scope: 1,
                  chunk_deleted: 1,
                  outside_department_scope: 1,
                  stale_chunk_policy_version: 1
                }
              }} =
               ReadModels.rebuild_user_access_projection(
                 tenant.id,
                 user.id,
                 "policy_v14",
                 @now
               )

      assert active_chunk_ids(tenant, user, "policy_v14") == [allowed_chunk.id]
      assert Repo.get!(AccessibleDocumentChunk, stale_projection.id).invalidated_at == @now
      refute high_sensitivity_chunk.id in active_chunk_ids(tenant, user, "policy_v14")
      refute deleted_chunk.id in active_chunk_ids(tenant, user, "policy_v14")
      refute sales_chunk.id in active_chunk_ids(tenant, user, "policy_v14")
      refute stale_policy_chunk.id in active_chunk_ids(tenant, user, "policy_v14")
    end

    test "rebuild is idempotent for the same user policy version" do
      %{tenant: tenant, user: user, chunk: chunk} = fixture_scope(policy_version: "policy_v15")

      assert {:ok, %{projected: 1, skipped: 0, invalidated: 0}} =
               ReadModels.rebuild_user_access_projection(
                 tenant.id,
                 user.id,
                 "policy_v15",
                 @now
               )

      assert active_chunk_ids(tenant, user, "policy_v15") == [chunk.id]

      assert {:ok, %{projected: 1, skipped: 0, invalidated: 1}} =
               ReadModels.rebuild_user_access_projection(
                 tenant.id,
                 user.id,
                 "policy_v15",
                 DateTime.add(@now, 60, :second)
               )

      assert active_chunk_ids(tenant, user, "policy_v15") == [chunk.id]
    end

    test "rebuild invalidates old rows and grants nothing for inactive users" do
      %{tenant: tenant, document: document, chunk: chunk} = fixture_scope(policy_version: "policy_v16")

      inactive_user =
        user_fixture(tenant,
          email: "inactive-read-model-user-#{System.unique_integer([:positive])}@example.com",
          status: "inactive",
          policy_version: "policy_v16"
        )

      assert {:ok, projection} =
               put_projection(tenant, inactive_user, document, chunk,
                 user_policy_version: "policy_v16",
                 projected_at: @now
               )

      assert {:ok,
              %{
                projected: 0,
                skipped: 1,
                invalidated: 1,
                skipped_reasons: %{inactive_user: 1}
              }} =
               ReadModels.rebuild_user_access_projection(
                 tenant.id,
                 inactive_user.id,
                 "policy_v16",
                 @now
               )

      assert active_chunk_ids(tenant, inactive_user, "policy_v16") == []
      assert Repo.get!(AccessibleDocumentChunk, projection.id).invalidated_at == @now
    end

    test "rebuild fails closed for missing sources and malformed scopes" do
      assert ReadModels.rebuild_user_access_projection(
               Ecto.UUID.generate(),
               Ecto.UUID.generate(),
               "policy_v1",
               @now
             ) == {:error, :user_projection_source_not_found}

      assert ReadModels.rebuild_user_access_projection(
               Ecto.UUID.generate(),
               Ecto.UUID.generate(),
               "policy_v1",
               "not-a-datetime"
             ) == {:error, :invalid_rebuild_scope}
    end
  end

  defp active_chunk_ids(tenant, user, user_policy_version) do
    ReadModels.accessible_chunk_ids(%{
      tenant_id: tenant.id,
      user_id: user.id,
      user_policy_version: user_policy_version
    })
  end

  defp put_projection(tenant, user, document, chunk, attrs) do
    ReadModels.put_accessible_document_chunk(%{
      tenant_id: tenant.id,
      user_id: user.id,
      chunk_id: chunk.id,
      document_id: document.id,
      user_policy_version: Keyword.fetch!(attrs, :user_policy_version),
      chunk_policy_version: chunk.policy_version,
      chunk_deleted_at: chunk.deleted_at,
      access_reason: Keyword.get(attrs, :access_reason, ["department_match"]),
      projected_at: Keyword.fetch!(attrs, :projected_at),
      invalidated_at: Keyword.get(attrs, :invalidated_at)
    })
  end

  defp build_and_put_projection(tenant, user, chunk, attrs) do
    decision =
      allow_decision(
        tenant_id: tenant.id,
        policy_version: Keyword.fetch!(attrs, :user_policy_version),
        access_reason: Keyword.get(attrs, :access_reason, ["department_match"])
      )

    with {:ok, projection_attrs} <-
           AccessibleDocumentChunkBuilder.build(
             user,
             chunk,
             decision,
             Keyword.fetch!(attrs, :projected_at)
           ) do
      projection_attrs
      |> Map.put(:invalidated_at, Keyword.get(attrs, :invalidated_at))
      |> ReadModels.put_accessible_document_chunk()
    end
  end

  defp allow_decision(attrs) do
    %Decision{
      decision: :allow,
      reason: Keyword.fetch!(attrs, :access_reason),
      policy_version: Keyword.fetch!(attrs, :policy_version),
      scope: %{
        "tenant_id" => Keyword.fetch!(attrs, :tenant_id),
        "departments" => ["finance"],
        "max_sensitivity" => 3
      }
    }
  end

  defp fixture_scope(attrs) do
    tenant = tenant_fixture("read-model-tenant")

    user =
      user_fixture(tenant,
        email: "read-model-user-#{System.unique_integer([:positive])}@example.com",
        policy_version: Keyword.fetch!(attrs, :policy_version)
      )

    document = document_fixture(tenant)
    chunk = chunk_fixture(tenant, document, policy_version: Keyword.fetch!(attrs, :policy_version))

    %{tenant: tenant, user: user, document: document, chunk: chunk}
  end
end
