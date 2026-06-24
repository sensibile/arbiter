defmodule Arbiter.Sync.OutboxReadModelDispatchTest do
  use ExUnit.Case, async: true

  alias Arbiter.Sync.OutboxEvent
  alias Arbiter.Sync.OutboxReadModelDispatch

  @now ~U[2026-06-24 11:00:00Z]

  describe "command/2" do
    test "maps user access invalidation events to read model invalidation commands" do
      tenant_id = Ecto.UUID.generate()
      user_id = Ecto.UUID.generate()

      event =
        outbox_event(
          tenant_id: tenant_id,
          aggregate_type: "user",
          aggregate_id: user_id,
          event_type: "invalidate_user_access_cache",
          payload: %{
            "tenant_id" => tenant_id,
            "user_id" => user_id,
            "previous_policy_version" => "policy_v12",
            "current_policy_version" => "policy_v13"
          }
        )

      assert OutboxReadModelDispatch.command(event, @now) ==
               {:ok,
                %{
                  operation: :invalidate_user_access,
                  tenant_id: tenant_id,
                  user_id: user_id,
                  user_policy_version: "policy_v12",
                  invalidated_at: @now
                }}
    end

    test "rejects payload identity mismatches" do
      tenant_id = Ecto.UUID.generate()
      user_id = Ecto.UUID.generate()

      event =
        outbox_event(
          tenant_id: tenant_id,
          aggregate_type: "user",
          aggregate_id: user_id,
          event_type: "invalidate_user_access_cache",
          payload: %{
            "tenant_id" => Ecto.UUID.generate(),
            "user_id" => user_id,
            "previous_policy_version" => "policy_v12"
          }
        )

      assert OutboxReadModelDispatch.command(event, @now) == {:error, :tenant_id_mismatch}

      event =
        outbox_event(
          tenant_id: tenant_id,
          aggregate_type: "user",
          aggregate_id: user_id,
          event_type: "invalidate_user_access_cache",
          payload: %{
            "tenant_id" => tenant_id,
            "user_id" => Ecto.UUID.generate(),
            "previous_policy_version" => "policy_v12"
          }
        )

      assert OutboxReadModelDispatch.command(event, @now) == {:error, :user_id_mismatch}
    end

    test "rejects unsupported commands and malformed payloads" do
      assert OutboxReadModelDispatch.command(
               outbox_event(event_type: "invalidate_tool_result_cache"),
               @now
             ) ==
               {:error, :unsupported_read_model_command}

      assert OutboxReadModelDispatch.command(
               outbox_event(
                 event_type: "invalidate_user_access_cache",
                 aggregate_type: "document"
               ),
               @now
             ) == {:error, :invalid_aggregate_type}

      assert OutboxReadModelDispatch.command(
               outbox_event(event_type: "invalidate_user_access_cache", payload: %{}),
               @now
             ) == {:error, :missing_tenant_id}

      assert OutboxReadModelDispatch.command(
               outbox_event(
                 event_type: "invalidate_user_access_cache",
                 payload: %{"tenant_id" => 123}
               ),
               @now
             ) == {:error, :invalid_tenant_id}

      tenant_id = Ecto.UUID.generate()
      user_id = Ecto.UUID.generate()

      assert OutboxReadModelDispatch.command(
               outbox_event(
                 tenant_id: tenant_id,
                 aggregate_id: user_id,
                 event_type: "invalidate_user_access_cache",
                 payload: %{"tenant_id" => tenant_id, "user_id" => user_id}
               ),
               @now
             ) == {:error, :missing_previous_policy_version}

      assert OutboxReadModelDispatch.command(
               outbox_event(
                 tenant_id: tenant_id,
                 aggregate_id: user_id,
                 event_type: "invalidate_user_access_cache",
                 payload: %{
                   "tenant_id" => tenant_id,
                   "user_id" => user_id,
                   "previous_policy_version" => nil
                 }
               ),
               @now
             ) == {:error, :invalid_previous_policy_version}

      assert OutboxReadModelDispatch.command(
               outbox_event(event_type: "invalidate_user_access_cache", payload: nil),
               @now
             ) == {:error, :missing_tenant_id}

      assert OutboxReadModelDispatch.command(%{}, @now) == {:error, :invalid_outbox_event}

      assert OutboxReadModelDispatch.command(outbox_event([]), "not-a-datetime") ==
               {:error, :invalid_outbox_event}
    end
  end

  defp outbox_event(attrs) do
    tenant_id = Keyword.get(attrs, :tenant_id, Ecto.UUID.generate())
    user_id = Keyword.get(attrs, :aggregate_id, Ecto.UUID.generate())

    defaults = %{
      tenant_id: tenant_id,
      event_type: "invalidate_user_access_cache",
      aggregate_type: "user",
      aggregate_id: user_id,
      payload: %{
        "tenant_id" => tenant_id,
        "user_id" => user_id,
        "previous_policy_version" => "policy_v1"
      },
      status: OutboxEvent.status_pending(),
      attempts: 0,
      available_at: @now
    }

    struct!(OutboxEvent, Map.merge(defaults, Map.new(attrs)))
  end
end
