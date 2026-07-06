defmodule Arbiter.Operations.HealthInfraTest do
  use Arbiter.DataCase, async: false

  alias Arbiter.Operations.Health
  alias Arbiter.Repo

  import Arbiter.SyncFixtures

  setup_all do
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)
    Ecto.Migrator.run(Repo, :up, all: true)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :manual)
    :ok
  end

  test "readiness checks database access and outbox backlog counts" do
    tenant = tenant_fixture("health-readiness")

    outbox_event_fixture(tenant, status: "pending")
    outbox_event_fixture(tenant, status: "processing", locked_at: ~U[2026-07-06 00:00:00Z])
    outbox_event_fixture(tenant, status: "failed", last_error: "cache_adapter_unavailable")

    assert Health.readiness() == %{
             status: "ready",
             checks: %{
               database: %{status: "ok"},
               outbox: %{status: "ok", pending: 1, processing: 1, failed: 1}
             }
           }
  end
end
