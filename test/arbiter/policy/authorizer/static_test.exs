defmodule Arbiter.Policy.Authorizer.StaticTest do
  use ExUnit.Case, async: true

  alias Arbiter.Policy.Authorizer
  alias Arbiter.Policy.Authorizer.Static

  import Arbiter.GatewayFixtures

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

    test "allows tenantless permissions and string-key policy maps" do
      policy =
        policy()
        |> put_in([:permissions, Access.at(0), :tenant_id], nil)
        |> string_key_policy()

      assert {:ok, decision} = Authorizer.authorize({Static, policy}, request())
      assert decision.decision == :allow
    end

    test "fails closed for malformed request identity fields" do
      assert Authorizer.authorize({Static, policy()}, request(tenant_id: "")) ==
               {:error, :invalid_tenant_id}

      assert Authorizer.authorize({Static, policy()}, request(user_id: "")) ==
               {:error, :invalid_user_id}

      assert Authorizer.authorize({Static, policy()}, request(action: "")) ==
               {:error, :invalid_action}

      assert Authorizer.authorize({Static, policy()}, request(resource_type: "")) ==
               {:error, :invalid_resource_type}

      assert Authorizer.authorize({Static, policy()}, request(user_snapshot: "invalid")) ==
               {:error, :invalid_user_snapshot}
    end

    test "fails closed for tenant mismatch and malformed ABAC attributes" do
      assert Authorizer.authorize(
               {Static, policy()},
               request(user_snapshot: %{"tenant_id" => "tenant_b"})
             ) == {:error, :missing_user_id}

      assert Authorizer.authorize(
               {Static, policy()},
               request(
                 user_snapshot: %{
                   "id" => "user_999",
                   "tenant_id" => "tenant_a",
                   "department_ids" => ["finance"],
                   "clearance_level" => 3
                 }
               )
             ) == {:error, :user_id_mismatch}

      assert Authorizer.authorize(
               {Static, policy()},
               request(
                 user_snapshot: %{
                   "id" => "user_123",
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
                   "id" => "user_123",
                   "tenant_id" => "tenant_a",
                   "department_ids" => ["finance"],
                   "clearance_level" => "high"
                 }
               )
             ) == {:error, :invalid_user_clearance_level}

      assert Authorizer.authorize(
               {Static, policy()},
               request(
                 user_snapshot: %{
                   "id" => "user_123",
                   "tenant_id" => 123,
                   "department_ids" => ["finance"],
                   "clearance_level" => 3
                 }
               )
             ) == {:error, :invalid_user_tenant_id}

      assert Authorizer.authorize(
               {Static, policy()},
               request(
                 user_snapshot: %{
                   "id" => "user_123",
                   "tenant_id" => "tenant_a",
                   "clearance_level" => 3
                 }
               )
             ) == {:error, :missing_user_department_ids}

      assert Authorizer.authorize(
               {Static, policy()},
               request(
                 user_snapshot: %{
                   "id" => "user_123",
                   "tenant_id" => "tenant_a",
                   "department_ids" => [""],
                   "clearance_level" => 3
                 }
               )
             ) == {:error, :invalid_user_department_ids}

      assert Authorizer.authorize(
               {Static, policy()},
               request(
                 user_snapshot: %{
                   "id" => "user_123",
                   "tenant_id" => "tenant_a",
                   "department_ids" => ["finance"]
                 }
               )
             ) == {:error, :missing_user_clearance_level}
    end

    test "fails closed for malformed policy data" do
      assert Authorizer.authorize(
               {Static, Map.put(policy(), :policy_version, "")},
               request()
             ) == {:error, :invalid_policy_version}

      assert Authorizer.authorize(
               {Static, Map.put(policy(), :role_assignments, "invalid")},
               request()
             ) == {:error, :invalid_role_assignment}

      assert Authorizer.authorize(
               {Static, put_in(policy(), [:role_assignments, "user_123"], [""])},
               request()
             ) == {:error, :invalid_role_assignment}

      assert Authorizer.authorize(
               {Static, Map.put(policy(), :permissions, "invalid")},
               request()
             ) == {:error, :invalid_permissions}

      assert Authorizer.authorize(
               {Static, Map.put(policy(), :permissions, [%{role: "analyst"}])},
               request()
             ) == {:error, :invalid_permission}

      assert Authorizer.authorize(
               {Static, Map.put(policy(), :permissions, [:invalid])},
               request()
             ) == {:error, :invalid_permission}
    end

    test "rejects invalid authorizer inputs" do
      assert Authorizer.authorize(:not_an_authorizer, request()) == {:error, :invalid_authorizer}

      assert Authorizer.authorize({UnknownAuthorizer, policy()}, request()) ==
               {:error, :invalid_authorizer}

      assert Authorizer.authorize({"not_an_authorizer_module", policy()}, request()) ==
               {:error, :invalid_authorization_request}

      assert Authorizer.authorize({Static, policy()}, :not_a_request) ==
               {:error, :invalid_authorization_request}

      assert Static.authorize(:not_a_policy, request()) == {:error, :invalid_authorization_input}
    end

    test "builds a Gateway-compatible executor" do
      authorize = Authorizer.executor({Static, policy()})

      assert {:ok, decision} = authorize.(request())
      assert decision.decision == :allow
    end

    test "supports plain request maps with string keys" do
      request =
        request()
        |> Map.from_struct()
        |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)

      assert {:ok, decision} = Authorizer.authorize({Static, policy()}, request)
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

  defp string_key_policy(policy) do
    %{
      "policy_version" => policy.policy_version,
      "role_assignments" => policy.role_assignments,
      "permissions" =>
        Enum.map(policy.permissions, fn permission ->
          Map.new(permission, fn {key, value} -> {Atom.to_string(key), value} end)
        end)
    }
  end

  defp request(attrs \\ []), do: tool_call(attrs)
end
