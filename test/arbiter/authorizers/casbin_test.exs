defmodule Arbiter.Authorizers.CasbinTest do
  use ExUnit.Case, async: true

  alias Arbiter.Authorizers.Casbin
  alias Arbiter.Gateway.ToolCall
  alias Arbiter.Policy.Authorizer

  describe "authorize/2" do
    test "allows when the injected Casbin enforcer allows" do
      enforce = fn tenant_id, user_id, action, resource_type ->
        tenant_id == "tenant_a" and user_id == "user_123" and action == "retrieve" and
          resource_type == "document_chunk"
      end

      assert {:ok, decision} =
               Authorizer.authorize(
                 {Casbin, %{policy_version: "policy_v12", roles: ["analyst"], enforce: enforce}},
                 request()
               )

      assert decision.decision == :allow
      assert decision.policy_version == "policy_v12"

      assert decision.scope == %{
               "tenant_id" => "tenant_a",
               "departments" => ["finance", "legal"],
               "max_sensitivity" => 3,
               "roles" => ["analyst"]
             }
    end

    test "denies without executing ABAC widening when Casbin denies" do
      enforce = fn _tenant_id, _user_id, _action, _resource_type -> false end

      assert {:ok, decision} =
               Authorizer.authorize(
                 {Casbin, %{policy_version: "policy_v12", enforce: enforce}},
                 request()
               )

      assert decision.decision == :deny
      assert decision.reason == ["rbac_denied"]
      assert decision.policy_version == "policy_v12"
      assert decision.scope == %{}
    end

    test "fails closed for malformed target and enforcer failures" do
      assert Authorizer.authorize({Casbin, %{enforce: fn _, _, _, _ -> true end}}, request()) ==
               {:error, :invalid_policy_version}

      assert Authorizer.authorize({Casbin, %{policy_version: "policy_v12"}}, request()) ==
               {:error, :invalid_casbin_enforcer}

      assert Authorizer.authorize(
               {Casbin,
                %{
                  policy_version: "policy_v12",
                  enforce: fn _, _, _, _ -> :maybe end
                }},
               request()
             ) == {:error, :invalid_casbin_decision}

      assert Authorizer.authorize(
               {Casbin,
                %{
                  policy_version: "policy_v12",
                  enforce: fn _, _, _, _ -> raise "casbin unavailable" end
                }},
               request()
             ) == {:error, :casbin_enforcer_failed}

      assert Authorizer.authorize(
               {Casbin,
                %{
                  policy_version: "policy_v12",
                  roles: [""],
                  enforce: fn _, _, _, _ -> true end
                }},
               request()
             ) == {:error, :invalid_roles}
    end
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
        "clearance_level" => 3,
        "policy_version" => "policy_v12"
      },
      resource_snapshot: %{"resource_type" => "document_chunk"}
    }

    struct!(ToolCall, Map.merge(defaults, Map.new(attrs)))
  end
end
