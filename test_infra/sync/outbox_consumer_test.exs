defmodule Arbiter.Sync.OutboxConsumerTest do
  use Arbiter.DataCase, async: false

  alias Arbiter.Repo
  alias Arbiter.Sync.OutboxConsumer
  alias Arbiter.Sync.OutboxEvent
  alias Arbiter.Tenants.Tenant

  @now ~U[2026-06-24 01:02:03Z]

  setup_all do
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)
    Ecto.Migrator.run(Repo, :up, all: true)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :manual)
    :ok
  end

  describe "claim_available/2" do
    test "claims available pending rows in PostgreSQL" do
      tenant = tenant_fixture()
      ready = outbox_event_fixture(tenant, available_at: ~U[2026-06-24 01:00:00Z])
      _future = outbox_event_fixture(tenant, available_at: ~U[2026-06-24 01:05:00Z])

      assert {:ok, [claimed]} = OutboxConsumer.claim_available(10, now: @now)

      assert claimed.id == ready.id
      assert claimed.status == "processing"
      assert claimed.attempts == 1
      assert claimed.locked_at == @now
      assert claimed.processed_at == nil

      assert Repo.get!(OutboxEvent, ready.id).status == "processing"
    end
  end

  describe "mark_processed/2 and mark_failed/3" do
    test "persists terminal states for claimed rows" do
      tenant = tenant_fixture()

      processed_event =
        tenant
        |> outbox_event_fixture()
        |> claim!()

      assert {:ok, processed} = OutboxConsumer.mark_processed(processed_event, now: @now)
      assert processed.status == "processed"
      assert processed.processed_at == @now
      assert processed.locked_at == nil
      assert processed.last_error == nil

      failed_event =
        tenant
        |> outbox_event_fixture()
        |> claim!()

      assert {:ok, failed} = OutboxConsumer.mark_failed(failed_event, "cache unavailable", now: @now)
      assert failed.status == "failed"
      assert failed.processed_at == @now
      assert failed.locked_at == nil
      assert failed.last_error == "cache unavailable"
    end

    test "rejects terminal marking before claim" do
      tenant = tenant_fixture()
      event = outbox_event_fixture(tenant)

      assert OutboxConsumer.mark_processed(event, now: @now) == {:error, :not_processing}
      assert Repo.get!(OutboxEvent, event.id).status == "pending"
    end

    test "rejects terminal marking when claim ownership does not match" do
      tenant = tenant_fixture()

      claimed =
        tenant
        |> outbox_event_fixture()
        |> claim!()

      claimed
      |> OutboxEvent.changeset(%{locked_at: ~U[2026-06-24 01:01:00Z]})
      |> Repo.update!()

      assert OutboxConsumer.mark_processed(claimed, now: @now) == {:error, :claim_mismatch}
      assert Repo.get!(OutboxEvent, claimed.id).status == "processing"
    end
  end

  defp claim!(event) do
    assert {:ok, [claimed]} = OutboxConsumer.claim_available(1, now: @now)
    assert claimed.id == event.id
    claimed
  end

  defp tenant_fixture do
    %Tenant{}
    |> Tenant.changeset(%{name: "outbox-consumer-tenant-#{System.unique_integer([:positive])}"})
    |> Repo.insert!()
  end

  defp outbox_event_fixture(tenant, attrs \\ []) do
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
          available_at: @now
        ],
        attrs
      )

    %OutboxEvent{}
    |> OutboxEvent.changeset(Map.new(attrs))
    |> Repo.insert!()
  end
end
