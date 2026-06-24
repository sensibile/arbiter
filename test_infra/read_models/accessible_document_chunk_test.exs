defmodule Arbiter.ReadModels.AccessibleDocumentChunkTest do
  use Arbiter.DataCase, async: false

  alias Arbiter.Documents.Chunk
  alias Arbiter.Documents.Document
  alias Arbiter.ReadModels
  alias Arbiter.ReadModels.AccessibleDocumentChunk
  alias Arbiter.Repo
  alias Arbiter.Tenants.Tenant
  alias Arbiter.Tenants.User

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

  defp fixture_scope(attrs) do
    tenant = tenant_fixture()

    user =
      %User{tenant_id: tenant.id}
      |> User.changeset(%{
        email: "read-model-user-#{System.unique_integer([:positive])}@example.com",
        role: "analyst",
        department_ids: ["finance"],
        clearance_level: 2,
        policy_version: Keyword.fetch!(attrs, :policy_version)
      })
      |> Repo.insert!()

    document = document_fixture(tenant)
    chunk = chunk_fixture(tenant, document, policy_version: Keyword.fetch!(attrs, :policy_version))

    %{tenant: tenant, user: user, document: document, chunk: chunk}
  end

  defp tenant_fixture do
    %Tenant{}
    |> Tenant.changeset(%{name: "read-model-tenant-#{System.unique_integer([:positive])}"})
    |> Repo.insert!()
  end

  defp document_fixture(tenant) do
    %Document{tenant_id: tenant.id}
    |> Document.changeset(%{
      source: "gdrive",
      department_id: "finance",
      classification: "internal",
      sensitivity_level: 1,
      status: "active",
      acl_version: "acl_v1"
    })
    |> Repo.insert!()
  end

  defp chunk_fixture(tenant, document, attrs) do
    %Chunk{tenant_id: tenant.id, document_id: document.id}
    |> Chunk.changeset(%{
      text: "renewal risk",
      department_id: "finance",
      sensitivity_level: 1,
      visibility: "department",
      acl_version: "acl_v1",
      policy_version: Keyword.get(attrs, :policy_version, "policy_v7"),
      deleted_at: Keyword.get(attrs, :deleted_at)
    })
    |> Repo.insert!()
  end
end
