defmodule Arbiter.Sync.OutboxProcessor do
  @moduledoc """
  Small orchestration boundary for one outbox processing pass.

  This module gives callers and future supervised workers a single operation for
  claiming available rows and executing supported propagation commands.
  """

  alias Arbiter.Sync.OutboxConsumer
  alias Arbiter.Sync.OutboxEvent

  @telemetry_event [:arbiter, :sync, :outbox, :processor, :run]

  def telemetry_event, do: @telemetry_event

  def run_once(limit, opts \\ [])

  def run_once(limit, opts) when is_integer(limit) and limit > 0 do
    start_time = System.monotonic_time()

    result =
      with {:ok, events} <- OutboxConsumer.claim_available(limit, opts) do
        results = Enum.map(events, &process_event(&1, opts))
        {:ok, summarize_results(events, results)}
      end

    emit_telemetry(result, limit, start_time)
    result
  end

  def run_once(limit, _opts) do
    result = {:error, :invalid_limit}

    emit_telemetry(result, limit, System.monotonic_time())
    result
  end

  defp process_event(%OutboxEvent{} = event, opts) do
    case OutboxConsumer.process_event(event, opts) do
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

  defp emit_telemetry({:ok, summary}, limit, start_time) do
    measurements =
      summary
      |> Map.take([:claimed, :processed, :failed, :errors])
      |> Map.put(:duration, System.monotonic_time() - start_time)

    :telemetry.execute(@telemetry_event, measurements, %{limit: limit, status: :ok})
  end

  defp emit_telemetry({:error, reason}, limit, start_time) do
    measurements = %{
      claimed: 0,
      processed: 0,
      failed: 0,
      errors: 1,
      duration: System.monotonic_time() - start_time
    }

    :telemetry.execute(@telemetry_event, measurements, %{
      limit: limit,
      status: :error,
      reason: reason
    })
  end
end
