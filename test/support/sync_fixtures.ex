defmodule Arbiter.SyncFixtures do
  @moduledoc false

  alias Arbiter.Documents.Chunk
  alias Arbiter.Documents.Document
  alias Arbiter.Repo
  alias Arbiter.Sync.OutboxEvent
  alias Arbiter.Tenants.Tenant
  alias Arbiter.Tenants.User

  @default_available_at ~U[2026-06-24 01:00:00Z]

  def tenant_fixture(prefix \\ "sync-tenant") do
    %Tenant{}
    |> Tenant.changeset(%{name: "#{prefix}-#{System.unique_integer([:positive])}"})
    |> Repo.insert!()
  end

  def outbox_event_fixture(tenant, attrs \\ []) do
    attrs =
      Keyword.merge(
        [
          tenant_id: tenant.id,
          event_type: "invalidate_user_access_cache",
          aggregate_type: "user",
          aggregate_id: Ecto.UUID.generate(),
          payload: %{"cache_key" => "user_access"},
          status: OutboxEvent.status_pending(),
          attempts: 0,
          available_at: @default_available_at
        ],
        attrs
      )

    %OutboxEvent{}
    |> OutboxEvent.changeset(Map.new(attrs))
    |> Repo.insert!()
  end

  def read_model_fixture_scope(attrs) do
    prefix = Keyword.get(attrs, :prefix, "sync-read-model")
    policy_version = Keyword.fetch!(attrs, :policy_version)
    tenant = tenant_fixture("#{prefix}-tenant")

    user =
      %User{tenant_id: tenant.id}
      |> User.changeset(%{
        email: "#{prefix}-user-#{System.unique_integer([:positive])}@example.com",
        role: "analyst",
        department_ids: ["finance"],
        clearance_level: 2,
        policy_version: policy_version
      })
      |> Repo.insert!()

    document =
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

    chunk =
      %Chunk{tenant_id: tenant.id, document_id: document.id}
      |> Chunk.changeset(%{
        text: "renewal risk",
        department_id: "finance",
        sensitivity_level: 1,
        visibility: "department",
        acl_version: "acl_v1",
        policy_version: policy_version
      })
      |> Repo.insert!()

    %{tenant: tenant, user: user, document: document, chunk: chunk}
  end

  def invalidate_user_access_payload(
        tenant_id,
        user_id,
        previous_policy_version,
        current_policy_version
      ) do
    %{
      "command" => "invalidate_user_access_cache",
      "tenant_id" => tenant_id,
      "user_id" => user_id,
      "previous_policy_version" => previous_policy_version,
      "current_policy_version" => current_policy_version
    }
  end
end
