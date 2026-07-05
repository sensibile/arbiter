defmodule Arbiter.Sync.OutboxReadModelDispatch do
  @moduledoc """
  Pure dispatcher from outbox propagation events to read model commands.

  This module only validates and reshapes event data. Repo updates and adapter
  calls belong to boundary modules.
  """

  alias Arbiter.Sync.OutboxEvent

  def command(%OutboxEvent{event_type: "invalidate_user_access_cache"} = event, %DateTime{} = now) do
    with :ok <- require_user_aggregate(event),
         {:ok, tenant_id} <- matching_payload_id(event, "tenant_id", event.tenant_id),
         {:ok, user_id} <- matching_payload_id(event, "user_id", event.aggregate_id),
         {:ok, previous_policy_version} <- fetch_payload_string(event, "previous_policy_version") do
      {:ok,
       %{
         operation: :invalidate_user_access,
         tenant_id: tenant_id,
         user_id: user_id,
         user_policy_version: previous_policy_version,
         invalidated_at: now
       }}
    end
  end

  def command(
        %OutboxEvent{event_type: "rebuild_user_access_projection"} = event,
        %DateTime{} = now
      ) do
    with :ok <- require_user_aggregate(event),
         {:ok, tenant_id} <- matching_payload_id(event, "tenant_id", event.tenant_id),
         {:ok, user_id} <- matching_payload_id(event, "user_id", event.aggregate_id),
         {:ok, user_policy_version} <- fetch_payload_string(event, "user_policy_version") do
      {:ok,
       %{
         operation: :rebuild_user_access_projection,
         tenant_id: tenant_id,
         user_id: user_id,
         user_policy_version: user_policy_version,
         rebuild_requested_at: now
       }}
    end
  end

  def command(%OutboxEvent{}, %DateTime{}), do: {:error, :unsupported_read_model_command}
  def command(_event, _now), do: {:error, :invalid_outbox_event}

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
end
