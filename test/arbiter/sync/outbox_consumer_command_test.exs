defmodule Arbiter.Sync.OutboxConsumerCommandTest do
  use ExUnit.Case, async: true

  alias Arbiter.Sync.OutboxConsumerCommand
  alias Arbiter.Sync.OutboxEvent

  @now ~U[2026-06-24 01:02:03Z]

  describe "claim/2" do
    test "marks available pending events as processing" do
      event =
        outbox_event(
          status: OutboxEvent.status_pending(),
          attempts: 1,
          available_at: ~U[2026-06-24 01:00:00Z]
        )

      assert {:ok, attrs} = OutboxConsumerCommand.claim(event, @now)

      assert attrs == %{
               status: "processing",
               attempts: 2,
               locked_at: @now,
               processed_at: nil,
               last_error: nil
             }
    end

    test "does not claim unavailable pending events" do
      event =
        outbox_event(
          status: OutboxEvent.status_pending(),
          available_at: ~U[2026-06-24 01:03:00Z]
        )

      assert OutboxConsumerCommand.claim(event, @now) == {:error, :not_available}
    end

    test "does not claim non-pending events" do
      event = outbox_event(status: OutboxEvent.status_processing())

      assert OutboxConsumerCommand.claim(event, @now) == {:error, :not_pending}
    end

    test "rejects invalid event input" do
      assert OutboxConsumerCommand.claim(%{}, @now) == {:error, :invalid_outbox_event}
    end
  end

  describe "mark_processed/2" do
    test "marks processing events as processed" do
      event =
        outbox_event(status: OutboxEvent.status_processing(), locked_at: ~U[2026-06-24 01:00:00Z])

      assert {:ok, attrs} = OutboxConsumerCommand.mark_processed(event, @now)

      assert attrs == %{
               status: "processed",
               processed_at: @now,
               locked_at: nil,
               last_error: nil
             }
    end

    test "rejects events that were not claimed" do
      event = outbox_event(status: OutboxEvent.status_pending())

      assert OutboxConsumerCommand.mark_processed(event, @now) == {:error, :not_processing}
    end

    test "rejects invalid processed input" do
      assert OutboxConsumerCommand.mark_processed(%{}, @now) == {:error, :invalid_outbox_event}
    end
  end

  describe "mark_failed/3" do
    test "marks processing events as failed with a normalized error" do
      event =
        outbox_event(status: OutboxEvent.status_processing(), locked_at: ~U[2026-06-24 01:00:00Z])

      assert {:ok, attrs} = OutboxConsumerCommand.mark_failed(event, :projection_missing, @now)

      assert attrs == %{
               status: "failed",
               processed_at: @now,
               locked_at: nil,
               last_error: "projection_missing"
             }
    end

    test "does not overwrite terminal events" do
      event = outbox_event(status: OutboxEvent.status_processed(), processed_at: @now)

      assert OutboxConsumerCommand.mark_failed(event, "late failure", @now) ==
               {:error, :already_terminal}
    end

    test "truncates long string errors" do
      event =
        outbox_event(status: OutboxEvent.status_processing(), locked_at: ~U[2026-06-24 01:00:00Z])

      error = String.duplicate("x", 1_100)

      assert {:ok, attrs} = OutboxConsumerCommand.mark_failed(event, error, @now)
      assert String.length(attrs.last_error) == 1_000
    end

    test "inspects non-string errors and rejects invalid failed input" do
      event =
        outbox_event(status: OutboxEvent.status_processing(), locked_at: ~U[2026-06-24 01:00:00Z])

      assert {:ok, attrs} = OutboxConsumerCommand.mark_failed(event, %{adapter: :cache}, @now)
      assert attrs.last_error == "%{adapter: :cache}"

      assert OutboxConsumerCommand.mark_failed(%{}, :failed, @now) ==
               {:error, :invalid_outbox_event}
    end
  end

  defp outbox_event(attrs) do
    defaults = %{
      tenant_id: Ecto.UUID.generate(),
      event_type: "invalidate_user_access_cache",
      aggregate_type: "user",
      aggregate_id: Ecto.UUID.generate(),
      payload: %{},
      status: OutboxEvent.status_pending(),
      attempts: 0,
      available_at: @now,
      locked_at: nil,
      processed_at: nil,
      last_error: nil
    }

    struct!(OutboxEvent, Map.merge(defaults, Map.new(attrs)))
  end
end
