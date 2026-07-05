defmodule Arbiter.Sync.OutboxConsumer do
  @moduledoc """
  Repo boundary for outbox consumer state changes.

  This module claims outbox rows, executes supported read model operations, and
  marks rows terminal. Cache, process, vector, and search adapters remain outside
  this boundary.
  """

  import Ecto.Query

  alias Arbiter.Repo
  alias Arbiter.ReadModels
  alias Arbiter.Sync.OutboxConsumerCommand
  alias Arbiter.Sync.OutboxEvent
  alias Arbiter.Sync.OutboxReadModelDispatch

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

  def process_read_model_event(%OutboxEvent{} = event, opts \\ []) do
    now = Keyword.get_lazy(opts, :now, &default_now/0)

    event
    |> OutboxReadModelDispatch.command(now)
    |> execute_read_model_command()
    |> mark_processed_or_failed(event, now)
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

  defp execute_read_model_command({:ok, %{operation: :invalidate_user_access} = command}) do
    ReadModels.invalidate_user_access(
      command.tenant_id,
      command.user_id,
      command.user_policy_version,
      command.invalidated_at
    )
  end

  defp execute_read_model_command({:ok, %{operation: :rebuild_user_access_projection} = command}) do
    ReadModels.rebuild_user_access_projection(
      command.tenant_id,
      command.user_id,
      command.user_policy_version,
      command.rebuild_requested_at
    )
  end

  defp execute_read_model_command({:error, reason}), do: {:error, reason}

  defp mark_processed_or_failed({:ok, _result}, event, now), do: mark_processed(event, now: now)

  defp mark_processed_or_failed({:error, reason}, event, now) do
    case mark_failed(event, reason, now: now) do
      {:ok, failed_event} -> {:error, failed_event}
      {:error, mark_reason} -> {:error, mark_reason}
    end
  end

  defp default_now do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
  end
end
