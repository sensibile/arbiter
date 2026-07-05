defmodule Arbiter.Sync.OutboxPayload do
  @moduledoc """
  Shared pure validation helpers for outbox event payloads.

  Dispatch modules use this helper to keep identity checks and payload error
  semantics consistent before any Repo or adapter boundary is called.
  """

  alias Arbiter.Sync.OutboxEvent

  def require_user_aggregate(%OutboxEvent{aggregate_type: "user"}), do: :ok
  def require_user_aggregate(%OutboxEvent{}), do: {:error, :invalid_aggregate_type}

  def matching_id(%OutboxEvent{} = event, key, expected_value) do
    case fetch_string(event, key) do
      {:ok, ^expected_value} -> {:ok, expected_value}
      {:ok, _other_value} -> {:error, :"#{key}_mismatch"}
      {:error, reason} -> {:error, reason}
    end
  end

  def fetch_string(%OutboxEvent{payload: payload}, key) when is_map(payload) do
    case Map.fetch(payload, key) do
      {:ok, value} when is_binary(value) and value != "" -> {:ok, value}
      {:ok, _invalid_value} -> {:error, :"invalid_#{key}"}
      :error -> {:error, :"missing_#{key}"}
    end
  end

  def fetch_string(%OutboxEvent{}, key), do: {:error, :"missing_#{key}"}
end
