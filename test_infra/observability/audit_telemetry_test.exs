defmodule Arbiter.Observability.AuditTelemetryInfraTest do
  use Arbiter.DataCase, async: false

  alias Arbiter.Observability.AuditTelemetry
  alias Arbiter.Policy.PolicyDecision
  alias Arbiter.Repo
  alias Arbiter.Retrieval.RetrievalTrace

  import Arbiter.DomainFixtures

  setup_all do
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)
    Ecto.Migrator.run(Repo, :up, all: true)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :manual)
    :ok
  end

  setup do
    attach_audit_telemetry()
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

  defp fixture_scope do
    tenant = tenant_fixture("audit-telemetry-tenant")

    user =
      user_fixture(tenant,
        email: "audit-telemetry-#{System.unique_integer([:positive])}@example.com"
      )

    agent_run = agent_run_fixture(tenant, user)

    %{tenant: tenant, user: user, agent_run: agent_run}
  end

  defp retrieval_event(%{tenant: tenant, user: user, agent_run: agent_run}, attrs) do
    Map.merge(
      %{
        event_type: "retrieval_decision",
        tenant_id: tenant.id,
        user_id: user.id,
        agent_run_id: agent_run.id,
        tool: "semantic_search",
        action: "retrieve",
        resource_type: "document_chunk",
        decision: "allow",
        reason: ["same_tenant"],
        policy_version: "policy_v12",
        retrieved_chunk_ids: [],
        accepted_chunk_ids: [],
        rejected_chunk_ids: [],
        applied_filter: %{},
        user_snapshot: %{"id" => user.id, "tenant_id" => tenant.id},
        resource_snapshot: %{"resource_type" => "document_chunk"},
        status: "allowed"
      },
      attrs
    )
  end
end
