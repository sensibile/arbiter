defmodule Arbiter.Policy.AuthorizationRequestTest do
  use ExUnit.Case, async: true

  alias Arbiter.Gateway.ToolCall
  alias Arbiter.Policy.AuthorizationRequest

  test "normalizes gateway tool calls into explicit authorizer requests" do
    assert {:ok, request} = AuthorizationRequest.normalize(tool_call())

    assert %AuthorizationRequest{} = request
    assert request.tenant_id == "tenant_a"
    assert request.user_id == "user_123"
    assert request.action == "retrieve"
    assert request.resource_type == "document_chunk"
    assert request.resource_id == nil
    assert request.user_snapshot["id"] == "user_123"
  end

  test "normalizes plain maps with string keys and optional resource ids" do
    assert {:ok, request} =
             AuthorizationRequest.normalize(%{
               "tenant_id" => "tenant_a",
               "user_id" => "user_123",
               "agent_run_id" => "run_456",
               "tool" => "semantic_search",
               "action" => "retrieve",
               "resource_type" => "document_chunk",
               "resource_id" => "chunk_123",
               "query" => %{"text" => "renewal"},
               "user_snapshot" => %{"id" => "user_123", "tenant_id" => "tenant_a"},
               "resource_snapshot" => %{"resource_type" => "document_chunk"}
             })

    assert request.resource_id == "chunk_123"
    assert request.query == %{"text" => "renewal"}
    assert request.resource_snapshot == %{"resource_type" => "document_chunk"}
  end

  test "fails closed for malformed required and optional fields" do
    assert AuthorizationRequest.normalize(%{}) == {:error, :invalid_tenant_id}

    assert AuthorizationRequest.normalize(tool_call(tenant_id: "")) ==
             {:error, :invalid_tenant_id}

    assert AuthorizationRequest.normalize(tool_call(user_id: "")) == {:error, :invalid_user_id}
    assert AuthorizationRequest.normalize(tool_call(action: "")) == {:error, :invalid_action}

    assert AuthorizationRequest.normalize(tool_call(resource_type: "")) ==
             {:error, :invalid_resource_type}

    assert AuthorizationRequest.normalize(tool_call(resource_id: "")) ==
             {:error, :invalid_resource_id}

    assert AuthorizationRequest.normalize(tool_call(user_snapshot: "invalid")) ==
             {:error, :invalid_user_snapshot}

    assert AuthorizationRequest.normalize(tool_call(query: "invalid")) ==
             {:error, :invalid_query}
  end

  test "revalidates already-built request structs" do
    request = struct!(AuthorizationRequest, Map.put(valid_attrs(), :tenant_id, ""))

    assert AuthorizationRequest.normalize(request) == {:error, :invalid_tenant_id}
  end

  defp tool_call(attrs \\ []) do
    struct!(ToolCall, Map.merge(valid_attrs(), Map.new(attrs)))
  end

  defp valid_attrs do
    %{
      tenant_id: "tenant_a",
      user_id: "user_123",
      agent_run_id: "run_456",
      tool: "semantic_search",
      action: "retrieve",
      resource_type: "document_chunk",
      query: %{"text" => "renewal risk"},
      user_snapshot: %{
        "id" => "user_123",
        "tenant_id" => "tenant_a",
        "department_ids" => ["finance", "legal"],
        "clearance_level" => 3
      },
      resource_snapshot: %{"resource_type" => "document_chunk"}
    }
  end
end
