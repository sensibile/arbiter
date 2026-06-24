defmodule Arbiter.Sync.OutboxConsumerCommand do
  @moduledoc """
  Pure outbox consumer state transitions.

  This module returns row updates as data. Repo transactions, row locks, clocks,
  cache adapters, and vector/search adapters belong to boundary modules.
  """

  alias Arbiter.Sync.OutboxEvent

  def claim(%OutboxEvent{} = event, %DateTime{} = now) do
    cond do
      event.status != OutboxEvent.status_pending() ->
        {:error, :not_pending}

      DateTime.compare(event.available_at, now) == :gt ->
        {:error, :not_available}

      true ->
        {:ok,
         %{
           status: OutboxEvent.status_processing(),
           attempts: event.attempts + 1,
           locked_at: now,
           processed_at: nil,
           last_error: nil
         }}
    end
  end

  def claim(_event, _now), do: {:error, :invalid_outbox_event}

  def mark_processed(%OutboxEvent{} = event, %DateTime{} = now) do
    with :ok <- require_processing(event) do
      {:ok,
       %{
         status: OutboxEvent.status_processed(),
         processed_at: now,
         locked_at: nil,
         last_error: nil
       }}
    end
  end

  def mark_processed(_event, _now), do: {:error, :invalid_outbox_event}

  def mark_failed(%OutboxEvent{} = event, error, %DateTime{} = now) do
    with :ok <- require_processing(event) do
      {:ok,
       %{
         status: OutboxEvent.status_failed(),
         processed_at: now,
         locked_at: nil,
         last_error: normalize_error(error)
       }}
    end
  end

  def mark_failed(_event, _error, _now), do: {:error, :invalid_outbox_event}

  defp require_processing(%OutboxEvent{} = event) do
    cond do
      event.status == OutboxEvent.status_processing() -> :ok
      event.status in OutboxEvent.terminal_statuses() -> {:error, :already_terminal}
      true -> {:error, :not_processing}
    end
  end

  defp normalize_error(error) when is_binary(error), do: String.slice(error, 0, 1_000)
  defp normalize_error(error) when is_atom(error), do: Atom.to_string(error)
  defp normalize_error(error), do: inspect(error, limit: 20, printable_limit: 1_000)
end
