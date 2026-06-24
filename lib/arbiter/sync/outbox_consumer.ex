defmodule Arbiter.Sync.OutboxConsumer do
  @moduledoc """
  Repo boundary for outbox consumer state changes.

  This module claims and marks outbox rows. It does not execute projection,
  cache, or vector/search adapters; supervised workers can compose those later.
  """

  import Ecto.Query

  alias Arbiter.Repo
  alias Arbiter.Sync.OutboxConsumerCommand
  alias Arbiter.Sync.OutboxEvent

  def claim_available(limit, opts \\ [])

  def claim_available(limit, opts) when is_integer(limit) and limit > 0 do
    now = Keyword.get_lazy(opts, :now, &default_now/0)

    Repo.transaction(fn ->
      OutboxEvent
      |> where([event], event.status == ^OutboxEvent.status_pending())
      |> where([event], event.available_at <= ^now)
      |> order_by([event], asc: event.available_at, asc: event.id)
      |> limit(^limit)
      |> lock("FOR UPDATE SKIP LOCKED")
      |> Repo.all()
      |> Enum.map(&claim_event!(&1, now))
    end)
  end

  def claim_available(_limit, _opts), do: {:error, :invalid_limit}

  def mark_processed(event, opts \\ [])

  def mark_processed(%OutboxEvent{} = event, opts) do
    now = Keyword.get_lazy(opts, :now, &default_now/0)
    update_claimed_from_command(event, OutboxConsumerCommand.mark_processed(event, now))
  end

  def mark_failed(event, error, opts \\ [])

  def mark_failed(%OutboxEvent{} = event, error, opts) do
    now = Keyword.get_lazy(opts, :now, &default_now/0)
    update_claimed_from_command(event, OutboxConsumerCommand.mark_failed(event, error, now))
  end

  defp claim_event!(event, now) do
    {:ok, attrs} = OutboxConsumerCommand.claim(event, now)

    event
    |> OutboxEvent.changeset(attrs)
    |> Repo.update!()
  end

  defp update_claimed_from_command(event, {:ok, attrs}) do
    updates = Map.put(attrs, :updated_at, Map.fetch!(attrs, :processed_at))

    {updated_count, _rows} =
      OutboxEvent
      |> where([row], row.id == ^event.id)
      |> where([row], row.status == ^OutboxEvent.status_processing())
      |> where([row], row.attempts == ^event.attempts)
      |> where([row], row.locked_at == ^event.locked_at)
      |> Repo.update_all(set: Map.to_list(updates))

    case updated_count do
      1 -> {:ok, Repo.get!(OutboxEvent, event.id)}
      0 -> {:error, :claim_mismatch}
    end
  end

  defp update_claimed_from_command(_event, {:error, reason}), do: {:error, reason}

  defp default_now do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
  end
end
