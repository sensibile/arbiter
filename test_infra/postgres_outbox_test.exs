defmodule Arbiter.Infra.PostgresOutboxTest do
  use Arbiter.DataCase, async: false

  alias Arbiter.Repo
  alias Arbiter.Sync.OutboxEvent
  alias Arbiter.Sync.RevokeSimulation

  import Arbiter.DomainFixtures

  setup_all do
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)
    Ecto.Migrator.run(Repo, :up, all: true)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :manual)
    :ok
  end

  test "revoke simulation persists outbox rows against a Testcontainers PostgreSQL database" do
    tenant = tenant_fixture("infra-tenant")

    user =
      user_fixture(tenant,
        email: "infra-user-#{System.unique_integer([:positive])}@example.com",
        policy_version: "policy_v12"
      )

    assert {:ok, result} =
             RevokeSimulation.revoke_user_access(user,
               reason: "infra_test_revoke",
               source: "testcontainers"
             )

    assert result.previous_policy_version == "policy_v12"
    assert result.current_policy_version == "policy_v13"
    assert length(result.outbox_events) == 3

    persisted_events =
      OutboxEvent
      |> Repo.all()
      |> Enum.sort_by(& &1.event_type)

    assert Enum.map(persisted_events, & &1.event_type) == [
             "invalidate_retrieval_result_cache",
             "invalidate_tool_result_cache",
             "invalidate_user_access_cache"
           ]

    assert Enum.all?(persisted_events, fn event ->
             event.tenant_id == tenant.id and
               event.aggregate_type == "user" and
               event.aggregate_id == user.id and
               event.status == "pending" and
               event.payload["previous_policy_version"] == "policy_v12" and
               event.payload["current_policy_version"] == "policy_v13"
           end)
  end
end
