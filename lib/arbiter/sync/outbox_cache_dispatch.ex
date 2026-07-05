defmodule Arbiter.Sync.OutboxCacheDispatch do
  @moduledoc """
  Pure dispatcher from outbox cache events to cache adapter commands.

  This module validates payload identity and returns adapter-neutral invalidation
  data. Adapter execution belongs to `Arbiter.Sync.OutboxConsumer`.
  """

  alias Arbiter.Sync.OutboxEvent

  @cache_events %{
    "invalidate_tool_result_cache" => :tool_result,
    "invalidate_retrieval_result_cache" => :retrieval_result
  }

  def command(%OutboxEvent{event_type: event_type} = event) do
    with {:ok, cache} <- cache_for_event(event_type),
         :ok <- require_user_aggregate(event),
         {:ok, tenant_id} <- matching_payload_id(event, "tenant_id", event.tenant_id),
         {:ok, user_id} <- matching_payload_id(event, "user_id", event.aggregate_id),
         {:ok, previous_policy_version} <- fetch_payload_string(event, "previous_policy_version"),
         {:ok, current_policy_version} <- fetch_payload_string(event, "current_policy_version") do
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

  defp require_user_aggregate(%OutboxEvent{aggregate_type: "user"}), do: :ok
  defp require_user_aggregate(%OutboxEvent{}), do: {:error, :invalid_aggregate_type}

  defp matching_payload_id(%OutboxEvent{} = event, key, expected_value) do
    case fetch_payload_string(event, key) do
      {:ok, ^expected_value} -> {:ok, expected_value}
      {:ok, _other_value} -> {:error, :"#{key}_mismatch"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_payload_string(%OutboxEvent{payload: payload}, key) when is_map(payload) do
    case Map.fetch(payload, key) do
      {:ok, value} when is_binary(value) and value != "" -> {:ok, value}
      {:ok, _invalid_value} -> {:error, :"invalid_#{key}"}
      :error -> {:error, :"missing_#{key}"}
    end
  end

  defp fetch_payload_string(%OutboxEvent{}, key), do: {:error, :"missing_#{key}"}

  defp optional_cache_key(%OutboxEvent{payload: payload}, command) when is_map(payload) do
    case Map.get(payload, "cache_key") do
      cache_key when is_binary(cache_key) and cache_key != "" ->
        Map.put(command, :cache_key, cache_key)

      _missing_or_invalid ->
        command
    end
  end

  defp optional_cache_key(%OutboxEvent{}, command), do: command
end
