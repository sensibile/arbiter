defmodule Arbiter.Sync.Outbox do
  @moduledoc """
  Transactional outbox helpers for sync and cache invalidation work.

  The outbox stores propagation commands. It is not an event-sourced state log.
  """

  alias Arbiter.Sync.OutboxEvent

  def invalidation_changesets(commands, opts \\ []) when is_list(commands) do
    available_at = Keyword.get_lazy(opts, :available_at, &default_available_at/0)

    Enum.map(commands, &invalidation_changeset(&1, available_at))
  end

  defp invalidation_changeset(command, available_at) do
    %OutboxEvent{}
    |> OutboxEvent.changeset(%{
      tenant_id: Map.fetch!(command, :tenant_id),
      event_type: Map.get(command, :event_type, Atom.to_string(Map.fetch!(command, :command))),
      aggregate_type: "user",
      aggregate_id: Map.fetch!(command, :user_id),
      payload: stringify_payload(command),
      status: "pending",
      attempts: 0,
      available_at: available_at
    })
  end

  defp stringify_payload(command) do
    command
    |> Enum.map(fn {key, value} -> {Atom.to_string(key), stringify_value(value)} end)
    |> Map.new()
  end

  defp stringify_value(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify_value(value), do: value

  defp default_available_at do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
  end
end
