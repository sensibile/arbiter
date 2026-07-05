defmodule Arbiter.Observability.GatewayTelemetry do
  @moduledoc """
  Bounded telemetry wrapper for Gateway tool calls.

  This module owns the telemetry side effect so `Arbiter.Gateway` can stay a
  pure orchestration boundary. Emitted metadata intentionally excludes tenant,
  user, agent run, query, and chunk identifiers.
  """

  alias Arbiter.Gateway
  alias Arbiter.Gateway.Error
  alias Arbiter.Gateway.Result

  @telemetry_event [:arbiter, :gateway, :tool_call, :run]

  def telemetry_event, do: @telemetry_event

  def run_tool_call(tool_call, opts) do
    start_time = System.monotonic_time()
    result = Gateway.run_tool_call(tool_call, opts)

    emit_telemetry(result, start_time)
    result
  end

  defp emit_telemetry(result, start_time) do
    audit_event = audit_event(result)

    measurements =
      audit_event
      |> count_measurements()
      |> Map.put(:duration, System.monotonic_time() - start_time)

    :telemetry.execute(@telemetry_event, measurements, metadata(audit_event))
  end

  defp audit_event({:ok, %Result{audit_event: audit_event}}), do: audit_event
  defp audit_event({:deny, %Result{audit_event: audit_event}}), do: audit_event
  defp audit_event({:error, %Error{audit_event: audit_event}}), do: audit_event

  defp count_measurements(audit_event) do
    %{
      retrieved_chunks: count(audit_event, :retrieved_chunk_ids),
      accepted_chunks: count(audit_event, :accepted_chunk_ids),
      rejected_chunks: count(audit_event, :rejected_chunk_ids)
    }
  end

  defp count(audit_event, field) do
    audit_event
    |> fetch(field, [])
    |> length()
  end

  defp metadata(audit_event) do
    %{
      status: fetch(audit_event, :status, "unknown"),
      decision: fetch(audit_event, :decision, "deny"),
      reason: primary_reason(fetch(audit_event, :reason, [])),
      tool: fetch(audit_event, :tool, "unknown"),
      action: fetch(audit_event, :action, "unknown"),
      resource_type: fetch(audit_event, :resource_type, "unknown"),
      policy_version: fetch(audit_event, :policy_version, "unknown")
    }
  end

  defp primary_reason([reason | _rest]) when is_binary(reason), do: reason
  defp primary_reason(_reasons), do: "unknown"

  defp fetch(map, key, default) when is_map(map) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end
end
