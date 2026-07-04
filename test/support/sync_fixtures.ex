defmodule Arbiter.SyncFixtures do
  @moduledoc false

  alias Arbiter.DomainFixtures
  alias Arbiter.Repo
  alias Arbiter.Sync.OutboxEvent

  @default_available_at ~U[2026-06-24 01:00:00Z]

  defdelegate tenant_fixture(prefix \\ "sync-tenant"), to: DomainFixtures

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
    tenant = DomainFixtures.tenant_fixture("#{prefix}-tenant")

    user =
      DomainFixtures.user_fixture(tenant,
        email: "#{prefix}-user-#{System.unique_integer([:positive])}@example.com",
        policy_version: policy_version
      )

    document = DomainFixtures.document_fixture(tenant)

    chunk = DomainFixtures.chunk_fixture(tenant, document, policy_version: policy_version)

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
