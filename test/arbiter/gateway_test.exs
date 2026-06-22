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
               query: caller_query,
               decision: "allow",
               reason: ["same_tenant", "active_user", "clearance_ok", "department_scope_matched"],
               policy_version: "policy_v12",
               user_snapshot: %{"id" => "user_123", "tenant_id" => "tenant_a"},
               resource_snapshot: %{"resource_type" => "document_chunk"},
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

    test "fails closed before execution when user policy snapshot is stale" do
      test_pid = self()

      execute = fn _guarded_query ->
        send(test_pid, :executed)
        {:ok, []}
      end

      tool_call =
        tool_call(user_snapshot: %{"id" => "user_123", "policy_version" => "policy_v11"})

      assert {:error, error} =
               Gateway.run_tool_call(tool_call,
                 tools: tools(execute),
                 authorize: authorize(allow_decision())
               )

      refute_received :executed
      assert error.reason == :stale_user_policy_version
      assert error.audit_event.decision == "deny"
      assert error.audit_event.reason == ["stale_user_policy_version"]
      assert error.audit_event.policy_version == "policy_v12"
      assert error.audit_event.status == "failed_closed"
    end

    test "fails closed before execution when resource policy snapshot is stale" do
      test_pid = self()

      execute = fn _guarded_query ->
        send(test_pid, :executed)
        {:ok, []}
      end

      tool_call =
        tool_call(
          resource_snapshot: %{
            "resource_type" => "document_chunk",
            "policy_version" => "policy_v11"
          }
        )

      assert {:error, error} =
               Gateway.run_tool_call(tool_call,
                 tools: tools(execute),
                 authorize: authorize(allow_decision())
               )

      refute_received :executed
      assert error.reason == :stale_resource_policy_version
      assert error.audit_event.decision == "deny"
      assert error.audit_event.reason == ["stale_resource_policy_version"]
      assert error.audit_event.policy_version == "policy_v12"
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

    test "fails closed when authorization returns an invalid shape" do
      assert {:error, error} =
               Gateway.run_tool_call(tool_call(),
                 tools: tools(fn _guarded_query -> {:ok, []} end),
                 authorize: fn _tool_call -> :allow end
               )

      assert error.reason == :authorization_failed
      assert error.audit_event.decision == "deny"
      assert error.audit_event.reason == ["authorization_failed"]
      assert error.audit_event.status == "failed_closed"
    end

    test "fails closed when authorization dependency is missing" do
      assert {:error, error} =
               Gateway.run_tool_call(tool_call(),
                 tools: tools(fn _guarded_query -> {:ok, []} end),
                 authorize: :missing_authorizer
               )

      assert error.reason == :authorization_failed
      assert error.audit_event.decision == "deny"
      assert error.audit_event.reason == ["authorization_failed"]
      assert error.audit_event.status == "failed_closed"
    end

    test "fails closed when the tool call shape is invalid" do
      assert {:error, error} =
               Gateway.run_tool_call(%{tool: "semantic_search"},
                 tools: tools(fn _guarded_query -> {:ok, []} end),
                 authorize: authorize(allow_decision())
               )

      assert error.reason == :invalid_tool_call
      assert error.audit_event.decision == "deny"
      assert error.audit_event.reason == ["invalid_tool_call"]
      assert error.audit_event.tenant_id == nil
      assert error.audit_event.status == "failed_closed"
    end

    test "fails closed before authorization when the tool is unknown" do
      test_pid = self()

      execute = fn _guarded_query ->
        send(test_pid, :executed)
        {:ok, []}
      end

      assert {:error, error} =
               Gateway.run_tool_call(tool_call(tool: "missing_tool"),
                 tools: tools(execute),
                 authorize: authorize(allow_decision())
               )

      refute_received :executed
      assert error.reason == :unknown_tool
      assert error.audit_event.decision == "deny"
      assert error.audit_event.reason == ["unknown_tool"]
      assert error.audit_event.status == "failed_closed"
    end

    test "fails closed before authorization when the tool registry is invalid" do
      assert {:error, error} =
               Gateway.run_tool_call(tool_call(),
                 tools: [],
                 authorize: authorize(allow_decision())
               )

      assert error.reason == :invalid_tool_registry
      assert error.audit_event.decision == "deny"
      assert error.audit_event.reason == ["invalid_tool_registry"]
      assert error.audit_event.status == "failed_closed"
    end

    test "fails closed before authorization when the tool contract mismatches" do
      mismatched_tools = %{
        "semantic_search" => %{
          action: "delete",
          resource_type: "document_chunk",
          kind: :vector_retrieval,
          execute: fn _guarded_query -> {:ok, []} end
        }
      }

      assert {:error, error} =
               Gateway.run_tool_call(tool_call(),
                 tools: mismatched_tools,
                 authorize: authorize(allow_decision())
               )

      assert error.reason == :tool_contract_mismatch
      assert error.audit_event.decision == "deny"
      assert error.audit_event.reason == ["tool_contract_mismatch"]
      assert error.audit_event.status == "failed_closed"
    end

    test "fails closed before authorization when the tool is missing an executor" do
      invalid_tools = %{
        "semantic_search" => %{
          action: "retrieve",
          resource_type: "document_chunk",
          kind: :vector_retrieval
        }
      }

      assert {:error, error} =
               Gateway.run_tool_call(tool_call(),
                 tools: invalid_tools,
                 authorize: authorize(allow_decision())
               )

      assert error.reason == :invalid_tool_contract
      assert error.audit_event.decision == "deny"
      assert error.audit_event.reason == ["invalid_tool_contract"]
      assert error.audit_event.status == "failed_closed"
    end

    test "allows matching policy snapshot versions and non-map snapshots" do
      assert {:ok, result} =
               Gateway.run_tool_call(
                 tool_call(
                   user_snapshot: %{"id" => "user_123", "policy_version" => "policy_v12"},
                   resource_snapshot: :not_loaded
                 ),
                 tools: tools(fn _guarded_query -> {:ok, []} end),
                 authorize: authorize(allow_decision())
               )

      assert result.audit_event.decision == "allow"
      assert result.audit_event.accepted_chunk_ids == []
      assert result.audit_event.status == "allowed"
    end

    test "fails closed when policy scope cannot compile into a retrieval filter" do
      invalid_scope_decision =
        allow_decision()
        |> Map.put(:scope, %{
          "tenant_id" => "tenant_a",
          "departments" => [],
          "max_sensitivity" => 3
        })

      assert {:error, error} =
               Gateway.run_tool_call(tool_call(),
                 tools: tools(fn _guarded_query -> {:ok, []} end),
                 authorize: authorize(invalid_scope_decision)
               )

      assert error.reason == :invalid_scope
      assert error.audit_event.decision == "deny"
      assert error.audit_event.reason == ["invalid_scope"]
      assert error.audit_event.status == "failed_closed"
    end

    test "fails closed when tool execution returns an error tuple" do
      assert {:error, error} =
               Gateway.run_tool_call(tool_call(),
                 tools: tools(fn _guarded_query -> {:error, :vector_store_unavailable} end),
                 authorize: authorize(allow_decision())
               )

      assert error.reason == :tool_execution_failed
      assert error.audit_event.decision == "deny"
      assert error.audit_event.reason == ["tool_execution_failed"]
      assert error.audit_event.status == "failed_closed"
    end

    test "fails closed when tool execution returns an invalid shape" do
      assert {:error, error} =
               Gateway.run_tool_call(tool_call(),
                 tools: tools(fn _guarded_query -> :ok end),
                 authorize: authorize(allow_decision())
               )

      assert error.reason == :tool_execution_failed
      assert error.audit_event.decision == "deny"
      assert error.audit_event.reason == ["tool_execution_failed"]
      assert error.audit_event.status == "failed_closed"
    end

    test "fails closed when tool execution raises or throws" do
      assert {:error, error} =
               Gateway.run_tool_call(tool_call(),
                 tools: tools(fn _guarded_query -> raise "vector store unavailable" end),
                 authorize: authorize(allow_decision())
               )

      assert error.reason == :tool_execution_failed
      assert error.audit_event.decision == "deny"
      assert error.audit_event.reason == ["tool_execution_failed"]
      assert error.audit_event.status == "failed_closed"

      assert {:error, error} =
               Gateway.run_tool_call(tool_call(),
                 tools: tools(fn _guarded_query -> throw(:vector_store_unavailable) end),
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
