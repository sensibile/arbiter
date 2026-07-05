defmodule Arbiter.Sync.OutboxCacheDispatch do
  @moduledoc """
  Pure dispatcher from outbox cache events to cache adapter commands.

  This module validates payload identity and returns adapter-neutral invalidation
  data. Adapter execution belongs to `Arbiter.Sync.OutboxConsumer`.
  """

  alias Arbiter.Sync.OutboxEvent
  alias Arbiter.Sync.OutboxPayload

  @cache_events %{
    "invalidate_tool_result_cache" => :tool_result,
    "invalidate_retrieval_result_cache" => :retrieval_result
  }

  def command(%OutboxEvent{event_type: event_type} = event) do
    with {:ok, cache} <- cache_for_event(event_type),
         :ok <- OutboxPayload.require_user_aggregate(event),
         {:ok, tenant_id} <- OutboxPayload.matching_id(event, "tenant_id", event.tenant_id),
         {:ok, user_id} <- OutboxPayload.matching_id(event, "user_id", event.aggregate_id),
         {:ok, previous_policy_version} <-
           OutboxPayload.fetch_string(event, "previous_policy_version"),
         {:ok, current_policy_version} <-
           OutboxPayload.fetch_string(event, "current_policy_version") do
      {:ok,
       optional_cache_key(event, %{
         operation: :invalidate_cache,
         cache: cache,
         tenant_id: tenant_id,
         user_id: user_id,
         previous_policy_version: previous_policy_version,
         current_policy_version: current_policy_version
       })}
    end
  end

  def command(_event), do: {:error, :invalid_outbox_event}

  defp cache_for_event(event_type) do
    case Map.fetch(@cache_events, event_type) do
      {:ok, cache} -> {:ok, cache}
      :error -> {:error, :unsupported_cache_command}
    end
  end

  defp optional_cache_key(%OutboxEvent{payload: payload}, command) when is_map(payload) do
    case Map.get(payload, "cache_key") do
      cache_key when is_binary(cache_key) and cache_key != "" ->
        Map.put(command, :cache_key, cache_key)

      _missing_or_invalid ->
        command
    end
  end
end
