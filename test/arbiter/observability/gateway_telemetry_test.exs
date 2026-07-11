defmodule Arbiter.Observability.GatewayTelemetryTest do
  use ExUnit.Case, async: true

  alias Arbiter.Observability.GatewayTelemetry
  alias Arbiter.Policy.Decision

  import Arbiter.GatewayFixtures
  import Arbiter.TelemetryHelpers

  setup do
    attach_telemetry(GatewayTelemetry.telemetry_event(), :gateway_telemetry)
  end

  test "emits bounded telemetry for allowed tool calls" do
    assert {:ok, result} =
             GatewayTelemetry.run_tool_call(tool_call(),
               tools:
                 tools(fn _guarded_query ->
                   {:ok,
                    [
                      chunk("chunk_1", tenant_id: "tenant_a"),
                      chunk("chunk_2", tenant_id: "tenant_b")
                    ]}
                 end),
               authorize:
                 authorize(
                   allow_decision(
                     scope: %{
                       "tenant_id" => "tenant_a",
                       "departments" => ["finance"],
                       "max_sensitivity" => 3
                     }
                   )
                 )
             )

    assert Enum.map(result.allowed_chunks, & &1.id) == ["chunk_1"]

    assert_receive {:gateway_telemetry, measurements, metadata}
    assert measurements.retrieved_chunks == 2
    assert measurements.accepted_chunks == 1
    assert measurements.rejected_chunks == 1
    assert is_integer(measurements.duration)
    assert measurements.duration >= 0

    assert metadata == %{
             status: "allowed",
             decision: "allow",
             reason: "same_tenant",
             tool: "semantic_search",
             action: "retrieve",
             resource_type: "document_chunk",
             policy_version: "policy_v12"
           }

    refute Map.has_key?(metadata, :tenant_id)
    refute Map.has_key?(metadata, :user_id)
    refute Map.has_key?(metadata, :agent_run_id)
    refute Map.has_key?(metadata, :query)
    refute Map.has_key?(metadata, :chunk_ids)
  end

  test "emits bounded telemetry for denied tool calls" do
    decision = %Decision{
      decision: :deny,
      reason: ["rbac_denied"],
      policy_version: "policy_v12",
      scope: %{}
    }

    assert {:deny, _result} =
             GatewayTelemetry.run_tool_call(tool_call(),
               tools: tools(fn _guarded_query -> {:ok, []} end),
               authorize: authorize(decision)
             )

    assert_receive {:gateway_telemetry, measurements, metadata}
    assert measurements.retrieved_chunks == 0
    assert measurements.accepted_chunks == 0
    assert measurements.rejected_chunks == 0

    assert metadata.status == "denied"
    assert metadata.decision == "deny"
    assert metadata.reason == "rbac_denied"
  end

  test "emits bounded telemetry for fail-closed tool calls" do
    assert {:error, _error} =
             GatewayTelemetry.run_tool_call(tool_call(tool: "missing_tool"),
               tools: tools(fn _guarded_query -> {:ok, []} end),
               authorize: authorize(allow_decision())
             )

    assert_receive {:gateway_telemetry, measurements, metadata}
    assert measurements.retrieved_chunks == 0
    assert measurements.accepted_chunks == 0
    assert measurements.rejected_chunks == 0

    assert metadata.status == "failed_closed"
    assert metadata.decision == "deny"
    assert metadata.reason == "unknown_tool"
    assert metadata.policy_version == "unknown"
  end

  defp tools(execute) do
    %{
      "semantic_search" => %{
        action: "retrieve",
        resource_type: "document_chunk",
        kind: :vector_retrieval,
        execute: execute
      }
    }
  end

  defp authorize(decision), do: fn _tool_call -> {:ok, decision} end

  defp chunk(id, attrs) do
    %{
      id: id,
      tenant_id: Keyword.fetch!(attrs, :tenant_id),
      department_id: "finance",
      sensitivity_level: 2,
      deleted_at: nil,
      policy_version: "policy_v12"
    }
  end
end
