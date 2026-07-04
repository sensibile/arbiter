defmodule Arbiter.Sync.OutboxProcessor do
  @moduledoc """
  Small orchestration boundary for one outbox processing pass.

  This module gives callers and future supervised workers a single operation for
  claiming available rows and executing supported propagation commands.
  """

  alias Arbiter.Sync.OutboxConsumer
  alias Arbiter.Sync.OutboxEvent

  def run_once(limit, opts \\ [])

  def run_once(limit, opts) when is_integer(limit) and limit > 0 do
    with {:ok, events} <- OutboxConsumer.claim_available(limit, opts) do
      results = Enum.map(events, &process_event(&1, opts))
      {:ok, summarize_results(events, results)}
    end
  end

  def run_once(_limit, _opts), do: {:error, :invalid_limit}

  defp process_event(%OutboxEvent{} = event, opts) do
    case OutboxConsumer.process_read_model_event(event, opts) do
      {:ok, processed_event} -> {:processed, processed_event}
      {:error, %OutboxEvent{} = failed_event} -> {:failed, failed_event}
      {:error, reason} -> {:error, reason, event}
    end
  end

  defp summarize_results(events, results) do
    counts = Enum.frequencies_by(results, &result_status/1)

    %{
      claimed: length(events),
      processed: Map.get(counts, :processed, 0),
      failed: Map.get(counts, :failed, 0),
      errors: Map.get(counts, :error, 0),
      results: results
    }
  end

  defp result_status({:processed, _event}), do: :processed
  defp result_status({:failed, _event}), do: :failed
  defp result_status({:error, _reason, _event}), do: :error
end
