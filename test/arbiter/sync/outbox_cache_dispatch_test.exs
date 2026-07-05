defmodule Arbiter.Sync.OutboxCacheDispatchTest do
  use ExUnit.Case, async: true

  alias Arbiter.Sync.OutboxCacheDispatch
  alias Arbiter.Sync.OutboxEvent

  @now ~U[2026-06-24 11:00:00Z]

  describe "command/1" do
    test "maps tool cache invalidation events to scoped cache commands" do
      tenant_id = Ecto.UUID.generate()
      user_id = Ecto.UUID.generate()

      event =
        outbox_event(
          tenant_id: tenant_id,
          aggregate_id: user_id,
          event_type: "invalidate_tool_result_cache",
          payload: %{
            "tenant_id" => tenant_id,
            "user_id" => user_id,
            "previous_policy_version" => "policy_v12",
            "current_policy_version" => "policy_v13",
            "cache_key" => "tool:cached"
          }
        )

      assert OutboxCacheDispatch.command(event) ==
               {:ok,
                %{
                  operation: :invalidate_cache,
                  cache: :tool_result,
                  tenant_id: tenant_id,
                  user_id: user_id,
                  previous_policy_version: "policy_v12",
                  current_policy_version: "policy_v13",
                  cache_key: "tool:cached"
                }}
    end

    test "maps retrieval cache invalidation events to scoped cache commands" do
      tenant_id = Ecto.UUID.generate()
      user_id = Ecto.UUID.generate()

      event =
        outbox_event(
          tenant_id: tenant_id,
          aggregate_id: user_id,
          event_type: "invalidate_retrieval_result_cache",
          payload: %{
            "tenant_id" => tenant_id,
            "user_id" => user_id,
            "previous_policy_version" => "policy_v12",
            "current_policy_version" => "policy_v13"
          }
        )

      assert {:ok, command} = OutboxCacheDispatch.command(event)
      assert command.cache == :retrieval_result
      assert command.previous_policy_version == "policy_v12"
      refute Map.has_key?(command, :cache_key)
    end

    test "rejects unsupported events and malformed payloads" do
      assert OutboxCacheDispatch.command(outbox_event(event_type: "unknown")) ==
               {:error, :unsupported_cache_command}

      assert OutboxCacheDispatch.command(
               outbox_event(
                 event_type: "invalidate_tool_result_cache",
                 aggregate_type: "document"
               )
             ) == {:error, :invalid_aggregate_type}

      assert OutboxCacheDispatch.command(
               outbox_event(event_type: "invalidate_tool_result_cache", payload: %{})
             ) == {:error, :missing_tenant_id}

      tenant_id = Ecto.UUID.generate()
      user_id = Ecto.UUID.generate()

      assert OutboxCacheDispatch.command(
               outbox_event(
                 tenant_id: tenant_id,
                 aggregate_id: user_id,
                 event_type: "invalidate_tool_result_cache",
                 payload: %{
                   "tenant_id" => Ecto.UUID.generate(),
                   "user_id" => user_id,
                   "previous_policy_version" => "policy_v1",
                   "current_policy_version" => "policy_v2"
                 }
               )
             ) == {:error, :tenant_id_mismatch}

      assert OutboxCacheDispatch.command(
               outbox_event(
                 tenant_id: tenant_id,
                 aggregate_id: user_id,
                 event_type: "invalidate_tool_result_cache",
                 payload: %{
                   "tenant_id" => tenant_id,
                   "user_id" => Ecto.UUID.generate(),
                   "previous_policy_version" => "policy_v1",
                   "current_policy_version" => "policy_v2"
                 }
               )
             ) == {:error, :user_id_mismatch}

      assert OutboxCacheDispatch.command(
               outbox_event(event_type: "invalidate_tool_result_cache", payload: nil)
             ) == {:error, :missing_tenant_id}

      assert OutboxCacheDispatch.command(
               outbox_event(
                 tenant_id: tenant_id,
                 aggregate_id: user_id,
                 event_type: "invalidate_tool_result_cache",
                 payload: %{
                   "tenant_id" => tenant_id,
                   "user_id" => user_id,
                   "previous_policy_version" => "policy_v1",
                   "current_policy_version" => ""
                 }
               )
             ) == {:error, :invalid_current_policy_version}

      assert OutboxCacheDispatch.command(%{}) == {:error, :invalid_outbox_event}
    end
  end

  defp outbox_event(attrs) do
    tenant_id = Keyword.get(attrs, :tenant_id, Ecto.UUID.generate())
    user_id = Keyword.get(attrs, :aggregate_id, Ecto.UUID.generate())

    defaults = %{
      tenant_id: tenant_id,
      event_type: "invalidate_tool_result_cache",
      aggregate_type: "user",
      aggregate_id: user_id,
      payload: %{
        "tenant_id" => tenant_id,
        "user_id" => user_id,
        "previous_policy_version" => "policy_v1",
        "current_policy_version" => "policy_v2"
      },
      status: OutboxEvent.status_pending(),
      attempts: 0,
      available_at: @now
    }

    struct!(OutboxEvent, Map.merge(defaults, Map.new(attrs)))
  end
end
