defmodule Arbiter.Observability.AuditTelemetryTest do
  use ExUnit.Case, async: true

  alias Arbiter.Observability.AuditTelemetry

  import Arbiter.TelemetryHelpers

  setup do
    attach_telemetry(AuditTelemetry.telemetry_event(), :audit_telemetry)
  end

  test "emits bounded telemetry for invalid retrieval decision input" do
    assert AuditTelemetry.record_retrieval_decision(:not_an_event) == {:error, :invalid_event}

    assert_receive {:audit_telemetry, measurements, metadata}
    assert is_integer(measurements.duration)
    assert measurements.duration >= 0

    assert metadata == %{
             operation: :retrieval_decision,
             status: :error,
             result: :invalid_event
           }
  end

  test "emits bounded telemetry for invalid answer lineage input" do
    assert AuditTelemetry.record_answer_lineage(:not_lineage) == {:error, :invalid_lineage}

    assert_receive {:audit_telemetry, _measurements, metadata}
    assert metadata == %{operation: :answer_lineage, status: :error, result: :invalid_lineage}
  end
end
