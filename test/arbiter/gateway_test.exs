defmodule Arbiter.GatewayTest do
  use ExUnit.Case, async: true

  alias Arbiter.Gateway
  alias Arbiter.Gateway.ToolCall
  alias Arbiter.Policy.Decision

  describe "run_tool_call/2" do
    test "authorizes, forces retrieval filters, post-validates chunks, and returns audit data" do
      caller_query = %{
        "text" => "renewal risk",
        "top_k" => 5,
        "filter" => %{"tenant_id" => "tenant_b"}
      }

      tool_call = tool_call(query: caller_query)
      test_pid = self()

      execute = fn guarded_query ->
        send(test_pid, {:executed, guarded_query})

        {:ok,
         [
           chunk("chunk_1",
             tenant_id: "tenant_a",
             department_id: "finance",
             sensitivity_level: 2
           ),
           chunk("chunk_2", tenant_id: "tenant_b", department_id: "finance", sensitivity_level: 2)
         ]}
      end

      assert {:ok, result} =
               Gateway.run_tool_call(tool_call,
                 tools: tools(execute),
                 authorize: authorize(allow_decision())
               )

      assert_receive {:executed, guarded_query}
      assert guarded_query.query == %{"text" => "renewal risk", "top_k" => 5}
      assert guarded_query.applied_filter["tenant_id"] == "tenant_a"

      assert Enum.map(result.allowed_chunks, & &1.id) == ["chunk_1"]
      assert result.rejected_chunk_ids == ["chunk_2"]
      assert result.policy_decision == allow_decision()

      assert result.audit_event == %{
               event_type: "retrieval_decision",
               tenant_id: "tenant_a",
               user_id: "user_123",
               agent_run_id: "run_456",
               tool: "semantic_search",
               action: "retrieve",
               resource_type: "document_chunk",
               decision: "allow",
               reason: ["same_tenant", "active_user", "clearance_ok", "department_scope_matched"],
               policy_version: "policy_v12",
               retrieved_chunk_ids: ["chunk_1", "chunk_2"],
               accepted_chunk_ids: ["chunk_1"],
               rejected_chunk_ids: ["chunk_2"],
               applied_filter: guarded_query.applied_filter,
               status: "allowed"
             }
    end

    test "denies without executing when policy denies" do
      test_pid = self()

      execute = fn _guarded_query ->
        send(test_pid, :executed)
        {:ok, []}
      end

      decision = %Decision{
        decision: :deny,
        reason: ["rbac_denied"],
        policy_version: "policy_v12",
        scope: %{}
      }

      assert {:deny, result} =
               Gateway.run_tool_call(tool_call(),
                 tools: tools(execute),
                 authorize: authorize(decision)
               )

      refute_received :executed
      assert result.allowed_chunks == []
      assert result.audit_event.decision == "deny"
      assert result.audit_event.reason == ["rbac_denied"]
      assert result.audit_event.status == "denied"
    end

    test "fails closed before execution when decision scope crosses tenants" do
      test_pid = self()

      execute = fn _guarded_query ->
        send(test_pid, :executed)
        {:ok, []}
      end

      decision =
        allow_decision()
        |> Map.put(:scope, %{
          "tenant_id" => "tenant_b",
          "departments" => ["finance"],
          "max_sensitivity" => 3
        })

      assert {:error, error} =
               Gateway.run_tool_call(tool_call(),
                 tools: tools(execute),
                 authorize: authorize(decision)
               )

      refute_received :executed
      assert error.reason == :tenant_scope_mismatch
      assert error.audit_event.decision == "deny"
      assert error.audit_event.reason == ["tenant_scope_mismatch"]
      assert error.audit_event.status == "failed_closed"
    end

    test "fails closed and audits when retrieved chunks cannot be validated" do
      execute = fn _guarded_query ->
        {:ok, [%{id: "chunk_1", tenant_id: "tenant_a"}]}
      end

      assert {:error, error} =
               Gateway.run_tool_call(tool_call(),
                 tools: tools(execute),
                 authorize: authorize(allow_decision())
               )

      assert error.reason == :retrieval_validation_failed
      assert error.audit_event.decision == "deny"
      assert error.audit_event.reason == ["retrieval_validation_failed"]
      assert error.audit_event.retrieved_chunk_ids == ["chunk_1"]
      assert error.audit_event.accepted_chunk_ids == []
      assert error.audit_event.status == "failed_closed"
    end

    test "fails closed when authorization cannot complete" do
      assert {:error, error} =
               Gateway.run_tool_call(tool_call(),
                 tools: tools(fn _guarded_query -> {:ok, []} end),
                 authorize: fn _tool_call -> {:error, :policy_store_unavailable} end
               )

      assert error.reason == :authorization_failed
      assert error.audit_event.decision == "deny"
      assert error.audit_event.reason == ["authorization_failed"]
      assert error.audit_event.status == "failed_closed"
    end

    test "fails closed when tool execution raises" do
      assert {:error, error} =
               Gateway.run_tool_call(tool_call(),
                 tools: tools(fn _guarded_query -> raise "vector store unavailable" end),
                 authorize: authorize(allow_decision())
               )

      assert error.reason == :tool_execution_failed
      assert error.audit_event.decision == "deny"
      assert error.audit_event.reason == ["tool_execution_failed"]
      assert error.audit_event.status == "failed_closed"
    end
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

  defp tool_call(attrs \\ []) do
    defaults = %{
      tenant_id: "tenant_a",
      user_id: "user_123",
      agent_run_id: "run_456",
      tool: "semantic_search",
      action: "retrieve",
      resource_type: "document_chunk",
      query: %{"text" => "renewal risk"},
      user_snapshot: %{"id" => "user_123", "tenant_id" => "tenant_a"},
      resource_snapshot: %{"resource_type" => "document_chunk"}
    }

    struct!(ToolCall, Map.merge(defaults, Map.new(attrs)))
  end

  defp allow_decision do
    %Decision{
      decision: :allow,
      reason: ["same_tenant", "active_user", "clearance_ok", "department_scope_matched"],
      policy_version: "policy_v12",
      scope: %{
        "tenant_id" => "tenant_a",
        "departments" => ["finance", "legal"],
        "max_sensitivity" => 3
      }
    }
  end

  defp chunk(id, attrs) do
    attrs
    |> Keyword.put_new(:deleted_at, nil)
    |> Keyword.put_new(:policy_version, "policy_v12")
    |> Keyword.put(:id, id)
    |> Map.new()
  end
end
