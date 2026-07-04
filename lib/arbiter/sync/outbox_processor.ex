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

      {:ok,
       %{
         claimed: length(events),
         processed: Enum.count(results, &match?({:processed, _event}, &1)),
         failed: Enum.count(results, &match?({:failed, _event}, &1)),
         errors: Enum.count(results, &match?({:error, _reason, _event}, &1)),
         results: results
       }}
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
end
