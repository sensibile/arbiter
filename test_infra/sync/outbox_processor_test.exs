defmodule Arbiter.Sync.OutboxProcessorTest do
  use Arbiter.DataCase, async: false

  alias Arbiter.ReadModels
  alias Arbiter.ReadModels.AccessibleDocumentChunk
  alias Arbiter.Repo
  alias Arbiter.Sync.OutboxEvent
  alias Arbiter.Sync.OutboxProcessor

  import Arbiter.SyncFixtures

  @now ~U[2026-06-24 02:00:00Z]

  setup_all do
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)
    Ecto.Migrator.run(Repo, :up, all: true)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :manual)
    :ok
  end

  describe "run_once/2" do
    test "returns an empty summary when no rows are available" do
      assert {:ok, %{claimed: 0, processed: 0, failed: 0, errors: 0, results: []}} =
               OutboxProcessor.run_once(10, now: @now)
    end

    test "emits bounded processing telemetry without row identifiers" do
      attach_processor_telemetry()

      tenant = tenant_fixture("outbox-processor-telemetry")
      user_id = Ecto.UUID.generate()

      outbox_event_fixture(tenant,
        aggregate_id: user_id,
        payload: invalidate_user_access_payload(tenant.id, user_id, "policy_v1", "policy_v2")
      )

      assert {:ok, %{claimed: 1, processed: 1, failed: 0, errors: 0}} =
               OutboxProcessor.run_once(10, now: @now)

      assert_receive {:outbox_processor_telemetry, measurements, metadata}

      assert %{
               claimed: 1,
               processed: 1,
               failed: 0,
               errors: 0,
               duration: duration
             } = measurements

      assert is_integer(duration)
      assert duration >= 0
      assert metadata == %{limit: 10, status: :ok}
    end

    test "supports a one-argument processing pass with the default clock" do
      tenant = tenant_fixture("outbox-processor-tenant")
      user_id = Ecto.UUID.generate()

      event =
        outbox_event_fixture(tenant,
          aggregate_id: user_id,
          payload: invalidate_user_access_payload(tenant.id, user_id, "policy_v1", "policy_v2"),
          available_at: ~U[2000-01-01 00:00:00Z]
        )

      assert {:ok, %{claimed: 1, processed: 1, failed: 0, errors: 0}} =
               OutboxProcessor.run_once(1)

      assert Repo.get!(OutboxEvent, event.id).status == OutboxEvent.status_processed()
    end

    test "claims pending read model invalidation events and processes them" do
      %{tenant: tenant, user: user, document: document, chunk: chunk} =
        read_model_fixture_scope(prefix: "outbox-processor", policy_version: "policy_v12")

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
        outbox_event_fixture(tenant,
          aggregate_id: user.id,
          payload: invalidate_user_access_payload(tenant.id, user.id, "policy_v12", "policy_v13")
        )

      assert {:ok,
              %{
                claimed: 1,
                processed: 1,
                failed: 0,
                errors: 0,
                results: [{:processed, processed_event}]
              }} = OutboxProcessor.run_once(10, now: @now)

      assert processed_event.id == event.id
      assert processed_event.status == OutboxEvent.status_processed()
      assert Repo.get!(AccessibleDocumentChunk, projection.id).invalidated_at == @now

      assert ReadModels.accessible_chunk_ids(%{
               tenant_id: tenant.id,
               user_id: user.id,
               user_policy_version: "policy_v12"
             }) == []
    end

    test "honors the claim limit and leaves later rows pending" do
      tenant = tenant_fixture("outbox-processor-tenant")
      user_id = Ecto.UUID.generate()

      first =
        outbox_event_fixture(tenant,
          aggregate_id: user_id,
          payload: invalidate_user_access_payload(tenant.id, user_id, "policy_v1", "policy_v2"),
          available_at: ~U[2026-06-24 01:00:00Z]
        )

      second =
        outbox_event_fixture(tenant,
          aggregate_id: user_id,
          payload: invalidate_user_access_payload(tenant.id, user_id, "policy_v2", "policy_v3"),
          available_at: ~U[2026-06-24 01:01:00Z]
        )

      assert {:ok, %{claimed: 1, processed: 1, failed: 0, errors: 0}} =
               OutboxProcessor.run_once(1, now: @now)

      assert Repo.get!(OutboxEvent, first.id).status == OutboxEvent.status_processed()
      assert Repo.get!(OutboxEvent, second.id).status == OutboxEvent.status_pending()
    end

    test "marks unsupported read model events failed without aborting the pass" do
      tenant = tenant_fixture("outbox-processor-tenant")
      user_id = Ecto.UUID.generate()

      unsupported =
        outbox_event_fixture(tenant,
          event_type: "invalidate_tool_result_cache",
          aggregate_id: user_id,
          payload: %{"cache_key" => "tool-result"}
        )

      supported =
        outbox_event_fixture(tenant,
          aggregate_id: user_id,
          payload: invalidate_user_access_payload(tenant.id, user_id, "policy_v3", "policy_v4")
        )

      assert {:ok,
              %{
                claimed: 2,
                processed: 1,
                failed: 1,
                errors: 0,
                results: results
              }} = OutboxProcessor.run_once(10, now: @now)

      assert {:failed, failed_event} =
               Enum.find(results, fn
                 {:failed, event} -> event.id == unsupported.id
                 _result -> false
               end)

      assert failed_event.status == OutboxEvent.status_failed()
      assert failed_event.last_error == "unsupported_read_model_command"
      assert Repo.get!(OutboxEvent, supported.id).status == OutboxEvent.status_processed()
    end

    test "rejects invalid limits before claiming rows" do
      assert OutboxProcessor.run_once(0, now: @now) == {:error, :invalid_limit}
      assert OutboxProcessor.run_once("1", now: @now) == {:error, :invalid_limit}
    end
  end

  defp attach_processor_telemetry do
    test_pid = self()
    handler_id = {__MODULE__, test_pid, System.unique_integer([:positive])}

    :ok =
      :telemetry.attach(
        handler_id,
        OutboxProcessor.telemetry_event(),
        fn _event, measurements, metadata, pid ->
          send(pid, {:outbox_processor_telemetry, measurements, metadata})
        end,
        test_pid
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end
end
