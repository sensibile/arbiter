defmodule Arbiter.Policy.Authorizer.StaticTest do
  use ExUnit.Case, async: true

  alias Arbiter.Gateway.ToolCall
  alias Arbiter.Policy.Authorizer
  alias Arbiter.Policy.Authorizer.Static

  describe "authorize/2" do
    test "allows matching RBAC permissions and builds ABAC retrieval scope" do
      assert {:ok, decision} = Authorizer.authorize({Static, policy()}, request())

      assert decision.decision == :allow
      assert decision.reason == ["rbac_allowed", "tenant_scope_matched", "abac_scope_built"]
      assert decision.policy_version == "policy_v12"

      assert decision.scope == %{
               "tenant_id" => "tenant_a",
               "departments" => ["finance", "legal"],
               "max_sensitivity" => 3,
               "roles" => ["analyst"]
             }
    end

    test "denies when RBAC permissions do not match action or resource" do
      assert {:ok, decision} =
               Authorizer.authorize({Static, policy()}, request(action: "delete"))

      assert decision.decision == :deny
      assert decision.reason == ["rbac_denied"]
      assert decision.policy_version == "policy_v12"
      assert decision.scope == %{}
    end

    test "fails closed for tenant mismatch and malformed ABAC attributes" do
      assert Authorizer.authorize(
               {Static, policy()},
               request(user_snapshot: %{"tenant_id" => "tenant_b"})
             ) == {:error, :missing_user_department_ids}

      assert Authorizer.authorize(
               {Static, policy()},
               request(
                 user_snapshot: %{
                   "tenant_id" => "tenant_b",
                   "department_ids" => ["finance"],
                   "clearance_level" => 3
                 }
               )
             ) == {:error, :tenant_scope_mismatch}

      assert Authorizer.authorize(
               {Static, policy()},
               request(
                 user_snapshot: %{
                   "tenant_id" => "tenant_a",
                   "department_ids" => ["finance"],
                   "clearance_level" => "high"
                 }
               )
             ) == {:error, :invalid_user_clearance_level}
    end

    test "rejects invalid authorizer inputs" do
      assert Authorizer.authorize(:not_an_authorizer, request()) == {:error, :invalid_authorizer}

      assert Authorizer.authorize({Static, policy()}, :not_a_request) ==
               {:error, :invalid_authorization_request}

      assert Static.authorize(:not_a_policy, request()) == {:error, :invalid_authorization_input}
    end

    test "builds a Gateway-compatible executor" do
      authorize = Authorizer.executor({Static, policy()})

      assert {:ok, decision} = authorize.(request())
      assert decision.decision == :allow
    end
  end

  defp policy do
    %{
      policy_version: "policy_v12",
      role_assignments: %{"user_123" => ["analyst"]},
      permissions: [
        %{
          role: "analyst",
          action: "retrieve",
          resource_type: "document_chunk",
          tenant_id: "tenant_a"
        }
      ]
    }
  end

  defp request(attrs \\ []) do
    defaults = %{
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

    struct!(ToolCall, Map.merge(defaults, Map.new(attrs)))
  end
end
