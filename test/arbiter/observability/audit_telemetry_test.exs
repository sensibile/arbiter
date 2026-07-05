defmodule Arbiter.Observability.AuditTelemetryTest do
  use ExUnit.Case, async: true

  alias Arbiter.Observability.AuditTelemetry

  setup do
    attach_audit_telemetry()
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

  defp attach_audit_telemetry do
    test_pid = self()
    handler_id = {__MODULE__, test_pid, System.unique_integer([:positive])}

    :ok =
      :telemetry.attach(
        handler_id,
        AuditTelemetry.telemetry_event(),
        fn _event, measurements, metadata, pid ->
          send(pid, {:audit_telemetry, measurements, metadata})
        end,
        test_pid
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end
end
