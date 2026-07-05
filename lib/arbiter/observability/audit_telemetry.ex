defmodule Arbiter.Observability.AuditTelemetry do
  @moduledoc """
  Bounded telemetry wrapper for audit persistence operations.

  The wrapper returns the exact `Arbiter.Audit` result while emitting aggregate
  operation status only. Metadata intentionally excludes tenant, user, agent,
  answer, policy decision, query, and chunk identifiers.
  """

  alias Arbiter.Audit

  @telemetry_event [:arbiter, :audit, :record, :run]

  def telemetry_event, do: @telemetry_event

  def record_retrieval_decision(event) do
    observe(:retrieval_decision, fn -> Audit.record_retrieval_decision(event) end)
  end

  def record_answer_lineage(attrs) do
    observe(:answer_lineage, fn -> Audit.record_answer_lineage(attrs) end)
  end

  defp observe(operation, call) do
    start_time = System.monotonic_time()
    result = call.()

    emit_telemetry(operation, result, start_time)
    result
  end

  defp emit_telemetry(operation, result, start_time) do
    :telemetry.execute(
      @telemetry_event,
      %{duration: System.monotonic_time() - start_time},
      %{operation: operation, status: status(result), result: result_kind(result)}
    )
  end

  defp status({:ok, _result}), do: :ok
  defp status({:error, _reason}), do: :error
  defp status({:error, _operation, _reason, _changes}), do: :error

  defp result_kind({:ok, _result}), do: :ok
  defp result_kind({:error, reason}) when is_atom(reason), do: reason
  defp result_kind({:error, operation, _reason, _changes}) when is_atom(operation), do: operation
  defp result_kind({:error, _reason}), do: :changeset_error
end
