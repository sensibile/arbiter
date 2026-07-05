defmodule Arbiter.Sync.OutboxConsumerTest do
  use Arbiter.DataCase, async: false

  alias Arbiter.ReadModels
  alias Arbiter.ReadModels.AccessibleDocumentChunk
  alias Arbiter.Repo
  alias Arbiter.Sync.OutboxConsumer
  alias Arbiter.Sync.OutboxEvent

  import Arbiter.SyncFixtures

  @now ~U[2026-06-24 01:02:03Z]

  setup_all do
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)
    Ecto.Migrator.run(Repo, :up, all: true)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :manual)
    :ok
  end

  describe "claim_available/2" do
    test "claims available pending rows in PostgreSQL" do
      tenant = tenant_fixture("outbox-consumer-tenant")
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

    test "rejects invalid claim limits" do
      assert OutboxConsumer.claim_available(0, now: @now) == {:error, :invalid_limit}
      assert OutboxConsumer.claim_available("1", now: @now) == {:error, :invalid_limit}
    end
  end

  describe "mark_processed/2 and mark_failed/3" do
    test "persists terminal states for claimed rows" do
      tenant = tenant_fixture("outbox-consumer-tenant")

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
      tenant = tenant_fixture("outbox-consumer-tenant")
      event = outbox_event_fixture(tenant)

      assert OutboxConsumer.mark_processed(event, now: @now) == {:error, :not_processing}
      assert Repo.get!(OutboxEvent, event.id).status == "pending"
    end

    test "rejects terminal marking when claim ownership does not match" do
      tenant = tenant_fixture("outbox-consumer-tenant")

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

    test "rejects failed marking when claim ownership does not match" do
      tenant = tenant_fixture("outbox-consumer-tenant")

      claimed =
        tenant
        |> outbox_event_fixture()
        |> claim!()

      claimed
      |> OutboxEvent.changeset(%{attempts: claimed.attempts + 1})
      |> Repo.update!()

      assert OutboxConsumer.mark_failed(claimed, :adapter_unavailable, now: @now) ==
               {:error, :claim_mismatch}

      assert Repo.get!(OutboxEvent, claimed.id).status == "processing"
    end
  end

  describe "process_read_model_event/2" do
    test "invalidates old user access projections and marks claimed event processed" do
      %{tenant: tenant, user: user, document: document, chunk: chunk} =
        read_model_fixture_scope(prefix: "outbox-consumer", policy_version: "policy_v12")

      assert {:ok, projection} =
               ReadModels.put_accessible_document_chunk(%{
                 tenant_id: tenant.id,
                 user_id: user.id,
                 chunk_id: chunk.id,
                 document_id: document.id,
                 user_policy_version: "policy_v12",
                 chunk_policy_version: chunk.policy_version,
                 chunk_deleted_at: nil,
                 access_reason: ["department_match"],
                 projected_at: @now
               })

      event =
        tenant
        |> outbox_event_fixture(
          aggregate_id: user.id,
          payload: invalidate_user_access_payload(tenant.id, user.id, "policy_v12", "policy_v13")
        )
        |> claim!()

      assert {:ok, processed_event} = OutboxConsumer.process_read_model_event(event, now: @now)
      assert processed_event.status == "processed"

      assert Repo.get!(AccessibleDocumentChunk, projection.id).invalidated_at == @now

      assert ReadModels.accessible_chunk_ids(%{
               tenant_id: tenant.id,
               user_id: user.id,
               user_policy_version: "policy_v12"
             }) == []
    end

    test "marks unsupported read model events failed" do
      tenant = tenant_fixture("outbox-consumer-tenant")

      event =
        tenant
        |> outbox_event_fixture(event_type: "invalidate_tool_result_cache")
        |> claim!()

      assert {:error, failed_event} = OutboxConsumer.process_read_model_event(event, now: @now)
      assert failed_event.status == "failed"
      assert failed_event.last_error == "unsupported_read_model_command"
    end

    test "marks known but unimplemented read model operations failed" do
      tenant = tenant_fixture("outbox-consumer-tenant")
      user_id = Ecto.UUID.generate()

      event =
        tenant
        |> outbox_event_fixture(
          event_type: "rebuild_user_access_projection",
          aggregate_id: user_id,
          payload: rebuild_user_access_payload(tenant.id, user_id, "policy_v13")
        )
        |> claim!()

      assert {:error, failed_event} = OutboxConsumer.process_read_model_event(event, now: @now)
      assert failed_event.status == "failed"
      assert failed_event.last_error == "unsupported_read_model_operation"
    end
  end

  defp claim!(event) do
    assert {:ok, [claimed]} = OutboxConsumer.claim_available(1, now: @now)
    assert claimed.id == event.id
    claimed
  end
end
