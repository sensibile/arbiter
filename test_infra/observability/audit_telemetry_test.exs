defmodule Arbiter.Observability.AuditTelemetryInfraTest do
  use Arbiter.DataCase, async: false

  alias Arbiter.Observability.AuditTelemetry
  alias Arbiter.Policy.PolicyDecision
  alias Arbiter.Repo
  alias Arbiter.Retrieval.RetrievalTrace

  import Arbiter.DomainFixtures
  import Arbiter.TelemetryHelpers

  setup_all do
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)
    Ecto.Migrator.run(Repo, :up, all: true)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :manual)
    :ok
  end

  setup do
    attach_telemetry(AuditTelemetry.telemetry_event(), :audit_telemetry)
  end

  test "emits bounded telemetry for persisted retrieval decisions" do
    scope = fixture_scope()

    assert {:ok, %{policy_decision: %PolicyDecision{}, retrieval_trace: %RetrievalTrace{}}} =
             AuditTelemetry.record_retrieval_decision(
               retrieval_event(scope, %{
                 retrieved_chunk_ids: [Ecto.UUID.generate()],
                 accepted_chunk_ids: [Ecto.UUID.generate()],
                 applied_filter: %{"tenant_id" => scope.tenant.id}
               })
             )

    assert_receive {:audit_telemetry, measurements, metadata}
    assert is_integer(measurements.duration)
    assert measurements.duration >= 0
    assert metadata == %{operation: :retrieval_decision, status: :ok, result: :ok}
    refute Map.has_key?(metadata, :tenant_id)
    refute Map.has_key?(metadata, :user_id)
    refute Map.has_key?(metadata, :agent_run_id)
    refute Map.has_key?(metadata, :chunk_id)
  end

  test "emits bounded telemetry for transaction rollback failures" do
    scope = fixture_scope()

    assert {:error, :retrieval_trace, _changeset, %{}} =
             scope
             |> retrieval_event(%{applied_filter: %{"tenant_id" => scope.tenant.id}})
             |> Map.delete(:tool)
             |> AuditTelemetry.record_retrieval_decision()

    assert_receive {:audit_telemetry, _measurements, metadata}
    assert metadata == %{operation: :retrieval_decision, status: :error, result: :retrieval_trace}
  end

  defp fixture_scope, do: retrieval_scope_fixture("audit-telemetry")
  defp retrieval_event(scope, attrs), do: retrieval_event_attrs(scope, attrs)
end
