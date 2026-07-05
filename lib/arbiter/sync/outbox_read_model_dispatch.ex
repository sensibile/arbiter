defmodule Arbiter.Sync.OutboxReadModelDispatch do
  @moduledoc """
  Pure dispatcher from outbox propagation events to read model commands.

  This module only validates and reshapes event data. Repo updates and adapter
  calls belong to boundary modules.
  """

  alias Arbiter.Sync.OutboxEvent
  alias Arbiter.Sync.OutboxPayload

  def command(%OutboxEvent{event_type: "invalidate_user_access_cache"} = event, %DateTime{} = now) do
    with :ok <- OutboxPayload.require_user_aggregate(event),
         {:ok, tenant_id} <- OutboxPayload.matching_id(event, "tenant_id", event.tenant_id),
         {:ok, user_id} <- OutboxPayload.matching_id(event, "user_id", event.aggregate_id),
         {:ok, previous_policy_version} <-
           OutboxPayload.fetch_string(event, "previous_policy_version") do
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
    with :ok <- OutboxPayload.require_user_aggregate(event),
         {:ok, tenant_id} <- OutboxPayload.matching_id(event, "tenant_id", event.tenant_id),
         {:ok, user_id} <- OutboxPayload.matching_id(event, "user_id", event.aggregate_id),
         {:ok, user_policy_version} <- OutboxPayload.fetch_string(event, "user_policy_version") do
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
end
