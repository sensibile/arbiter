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
