defmodule Arbiter.AuditTest do
  use Arbiter.DataCase, async: false

  alias Arbiter.Agents.AgentRun
  alias Arbiter.Audit
  alias Arbiter.Audit.AnswerLineage
  alias Arbiter.Policy.PolicyDecision
  alias Arbiter.Repo
  alias Arbiter.Retrieval.RetrievalTrace
  alias Arbiter.Tenants.Tenant
  alias Arbiter.Tenants.User

  setup_all do
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)
    Ecto.Migrator.run(Repo, :up, all: true)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :manual)
    :ok
  end

  describe "record_retrieval_decision/1" do
    test "records policy decision and retrieval trace in one audit transaction" do
      scope = %{tenant: tenant, user: user, agent_run: agent_run} = fixture_scope()

      event =
        retrieval_event(scope, %{
          reason: ["same_tenant", "active_user"],
          retrieved_chunk_ids: [Ecto.UUID.generate(), Ecto.UUID.generate()],
          applied_filter: %{"tenant_id" => tenant.id}
        })

      assert {:ok, %{policy_decision: policy_decision, retrieval_trace: retrieval_trace}} =
               Audit.record_retrieval_decision(event)

      assert policy_decision.tenant_id == tenant.id
      assert policy_decision.user_id == user.id
      assert policy_decision.decision == "allow"
      assert policy_decision.reason == ["same_tenant", "active_user"]
      assert policy_decision.user_snapshot == event.user_snapshot

      assert retrieval_trace.agent_run_id == agent_run.id
      assert retrieval_trace.tool == "semantic_search"
      assert retrieval_trace.query == %{}
      assert retrieval_trace.applied_filter == %{"tenant_id" => tenant.id}
      assert retrieval_trace.retrieved_chunk_ids == event.retrieved_chunk_ids

      assert Repo.aggregate(PolicyDecision, :count) == 1
      assert Repo.aggregate(RetrievalTrace, :count) == 1
    end

    test "records deny decisions without creating an empty retrieval trace" do
      event =
        fixture_scope()
        |> retrieval_event(%{
          decision: "deny",
          reason: ["rbac_denied"],
          status: "denied"
        })

      assert {:ok, %{policy_decision: policy_decision, retrieval_trace: nil}} =
               Audit.record_retrieval_decision(event)

      assert policy_decision.decision == "deny"
      assert policy_decision.reason == ["rbac_denied"]
      assert Repo.aggregate(PolicyDecision, :count) == 1
      assert Repo.aggregate(RetrievalTrace, :count) == 0
    end

    test "records rejected-only retrieval traces for failed-closed decisions" do
      %{tenant: tenant, user: user, agent_run: agent_run} = fixture_scope()

      rejected_chunk_id = Ecto.UUID.generate()

      event = %{
        "event_type" => "retrieval_decision",
        "tenant_id" => tenant.id,
        "user_id" => user.id,
        "agent_run_id" => agent_run.id,
        "tool" => "semantic_search",
        "action" => "retrieve",
        "resource_type" => "document_chunk",
        "decision" => "deny",
        "reason" => ["retrieval_validation_failed"],
        "policy_version" => "policy_v12",
        "retrieved_chunk_ids" => [rejected_chunk_id],
        "accepted_chunk_ids" => [],
        "rejected_chunk_ids" => [rejected_chunk_id],
        "applied_filter" => %{},
        "user_snapshot" => %{"id" => user.id, "tenant_id" => tenant.id},
        "resource_snapshot" => %{"resource_type" => "document_chunk"},
        "status" => "failed_closed"
      }

      assert {:ok, %{policy_decision: policy_decision, retrieval_trace: retrieval_trace}} =
               Audit.record_retrieval_decision(event)

      assert policy_decision.decision == "deny"
      assert retrieval_trace.rejected_chunk_ids == [rejected_chunk_id]
      assert retrieval_trace.applied_filter == %{}
      assert Repo.aggregate(PolicyDecision, :count) == 1
      assert Repo.aggregate(RetrievalTrace, :count) == 1
    end

    test "rejects invalid retrieval decision input" do
      assert {:error, :invalid_event} = Audit.record_retrieval_decision(:not_an_event)
    end

    test "fails closed when required audit fields are missing" do
      event = %{
        action: "retrieve",
        resource_type: "document_chunk",
        decision: "allow",
        reason: ["same_tenant"],
        policy_version: "policy_v12"
      }

      assert {:error, :policy_decision, changeset, %{}} =
               Audit.record_retrieval_decision(event)

      assert "can't be blank" in errors_on(changeset).tenant_id
    end

    test "rolls back policy decision when retrieval trace cannot be recorded" do
      scope = fixture_scope()

      event =
        scope
        |> retrieval_event(%{applied_filter: %{"tenant_id" => scope.tenant.id}})
        |> Map.delete(:tool)

      assert {:error, :retrieval_trace, changeset, %{}} =
               Audit.record_retrieval_decision(event)

      assert "can't be blank" in errors_on(changeset).tool
      assert Repo.aggregate(PolicyDecision, :count) == 0
      assert Repo.aggregate(RetrievalTrace, :count) == 0
    end
  end

  describe "record_answer_lineage/1" do
    test "records answer to used chunks and policy decisions" do
      %{tenant: tenant, user: user, agent_run: agent_run} = fixture_scope()

      policy_decision =
        %PolicyDecision{}
        |> PolicyDecision.changeset(%{
          tenant_id: tenant.id,
          user_id: user.id,
          action: "retrieve",
          resource_type: "document_chunk",
          decision: "allow",
          reason: ["same_tenant"],
          policy_version: "policy_v12",
          user_snapshot: %{"id" => user.id},
          resource_snapshot: %{"resource_type" => "document_chunk"}
        })
        |> Repo.insert!()

      attrs = %{
        answer_id: Ecto.UUID.generate(),
        agent_run_id: agent_run.id,
        tenant_id: tenant.id,
        user_id: user.id,
        used_chunks: [
          %{
            "chunk_id" => Ecto.UUID.generate(),
            "document_id" => Ecto.UUID.generate(),
            "policy_version" => "policy_v12"
          }
        ],
        policy_decision_ids: [policy_decision.id]
      }

      assert {:ok, %AnswerLineage{} = lineage} = Audit.record_answer_lineage(attrs)

      assert lineage.answer_id == attrs.answer_id
      assert lineage.agent_run_id == agent_run.id
      assert lineage.used_chunks == attrs.used_chunks
      assert lineage.policy_decision_ids == [policy_decision.id]
    end

    test "rejects answer lineage without used chunks or policy decisions" do
      scope = fixture_scope()

      assert {:error, changeset} =
               scope
               |> answer_lineage_attrs(%{used_chunks: [], policy_decision_ids: []})
               |> Audit.record_answer_lineage()

      assert "should have at least 1 item(s)" in errors_on(changeset).used_chunks
      assert "should have at least 1 item(s)" in errors_on(changeset).policy_decision_ids
    end

    test "rejects malformed used chunk lineage" do
      scope = fixture_scope()

      assert {:error, changeset} =
               scope
               |> answer_lineage_attrs(%{used_chunks: [%{"chunk_id" => "not-a-uuid"}]})
               |> Audit.record_answer_lineage()

      assert "must include chunk_id, document_id, and policy_version for every chunk" in errors_on(
               changeset
             ).used_chunks
    end

    test "rejects used chunk lineage with invalid UUID fields" do
      scope = fixture_scope()

      assert {:error, changeset} =
               scope
               |> answer_lineage_attrs(%{
                 used_chunks: [
                   %{
                     "chunk_id" => Ecto.UUID.generate(),
                     "document_id" => 123,
                     "policy_version" => "policy_v12"
                   }
                 ]
               })
               |> Audit.record_answer_lineage()

      assert "must include chunk_id, document_id, and policy_version for every chunk" in errors_on(
               changeset
             ).used_chunks
    end

    test "rejects invalid answer lineage input" do
      assert {:error, :invalid_lineage} = Audit.record_answer_lineage(:not_lineage)
    end
  end

  defp fixture_scope do
    tenant =
      %Tenant{}
      |> Tenant.changeset(%{name: "tenant-#{System.unique_integer([:positive])}"})
      |> Repo.insert!()

    user =
      %User{tenant_id: tenant.id}
      |> User.changeset(%{
        email: "user-#{System.unique_integer([:positive])}@example.com",
        role: "analyst"
      })
      |> Repo.insert!()

    agent_run =
      %AgentRun{tenant_id: tenant.id, user_id: user.id}
      |> AgentRun.changeset(%{question: "What changed?"})
      |> Repo.insert!()

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

  defp answer_lineage_attrs(%{tenant: tenant, user: user, agent_run: agent_run}, attrs) do
    Map.merge(
      %{
        answer_id: Ecto.UUID.generate(),
        agent_run_id: agent_run.id,
        tenant_id: tenant.id,
        user_id: user.id,
        used_chunks: [used_chunk()],
        policy_decision_ids: [Ecto.UUID.generate()]
      },
      attrs
    )
  end

  defp used_chunk do
    %{
      "chunk_id" => Ecto.UUID.generate(),
      "document_id" => Ecto.UUID.generate(),
      "policy_version" => "policy_v12"
    }
  end
end
