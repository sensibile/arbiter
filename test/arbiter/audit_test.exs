defmodule Arbiter.AuditTest do
  use Arbiter.DataCase, async: true

  alias Arbiter.Agents.AgentRun
  alias Arbiter.Audit
  alias Arbiter.Audit.AnswerLineage
  alias Arbiter.Policy.PolicyDecision
  alias Arbiter.Repo
  alias Arbiter.Retrieval.RetrievalTrace
  alias Arbiter.Tenants.Tenant
  alias Arbiter.Tenants.User

  describe "record_retrieval_decision/1" do
    test "records policy decision and retrieval trace in one audit transaction" do
      %{tenant: tenant, user: user, agent_run: agent_run} = fixture_scope()

      event = %{
        event_type: "retrieval_decision",
        tenant_id: tenant.id,
        user_id: user.id,
        agent_run_id: agent_run.id,
        tool: "semantic_search",
        action: "retrieve",
        resource_type: "document_chunk",
        decision: "allow",
        reason: ["same_tenant", "active_user"],
        policy_version: "policy_v12",
        retrieved_chunk_ids: [Ecto.UUID.generate(), Ecto.UUID.generate()],
        accepted_chunk_ids: [],
        rejected_chunk_ids: [],
        applied_filter: %{"tenant_id" => tenant.id},
        user_snapshot: %{"id" => user.id, "tenant_id" => tenant.id},
        resource_snapshot: %{"resource_type" => "document_chunk"},
        status: "allowed"
      }

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
      %{tenant: tenant, user: user, agent_run: agent_run} = fixture_scope()

      event = %{
        event_type: "retrieval_decision",
        tenant_id: tenant.id,
        user_id: user.id,
        agent_run_id: agent_run.id,
        tool: "semantic_search",
        action: "retrieve",
        resource_type: "document_chunk",
        decision: "deny",
        reason: ["rbac_denied"],
        policy_version: "policy_v12",
        retrieved_chunk_ids: [],
        accepted_chunk_ids: [],
        rejected_chunk_ids: [],
        applied_filter: %{},
        user_snapshot: %{"id" => user.id, "tenant_id" => tenant.id},
        resource_snapshot: %{"resource_type" => "document_chunk"},
        status: "denied"
      }

      assert {:ok, %{policy_decision: policy_decision, retrieval_trace: nil}} =
               Audit.record_retrieval_decision(event)

      assert policy_decision.decision == "deny"
      assert policy_decision.reason == ["rbac_denied"]
      assert Repo.aggregate(PolicyDecision, :count) == 1
      assert Repo.aggregate(RetrievalTrace, :count) == 0
    end

    test "fails closed when required audit fields are missing" do
      event = %{
        event_type: "retrieval_decision",
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
      %{tenant: tenant, user: user, agent_run: agent_run} = fixture_scope()

      event = %{
        event_type: "retrieval_decision",
        tenant_id: tenant.id,
        user_id: user.id,
        agent_run_id: agent_run.id,
        action: "retrieve",
        resource_type: "document_chunk",
        decision: "allow",
        reason: ["same_tenant"],
        policy_version: "policy_v12",
        retrieved_chunk_ids: [],
        accepted_chunk_ids: [],
        rejected_chunk_ids: [],
        applied_filter: %{"tenant_id" => tenant.id},
        user_snapshot: %{"id" => user.id, "tenant_id" => tenant.id},
        resource_snapshot: %{"resource_type" => "document_chunk"},
        status: "allowed"
      }

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
      %{tenant: tenant, user: user, agent_run: agent_run} = fixture_scope()

      assert {:error, changeset} =
               Audit.record_answer_lineage(%{
                 answer_id: Ecto.UUID.generate(),
                 agent_run_id: agent_run.id,
                 tenant_id: tenant.id,
                 user_id: user.id,
                 used_chunks: [],
                 policy_decision_ids: []
               })

      assert "should have at least 1 item(s)" in errors_on(changeset).used_chunks
      assert "should have at least 1 item(s)" in errors_on(changeset).policy_decision_ids
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
end
