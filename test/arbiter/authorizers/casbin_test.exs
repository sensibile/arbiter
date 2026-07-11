defmodule Arbiter.Authorizers.CasbinTest do
  use ExUnit.Case, async: true

  alias Arbiter.Authorizers.Casbin
  alias Arbiter.Policy.Authorizer

  import Arbiter.GatewayFixtures

  describe "authorize/2" do
    test "allows when the injected Casbin enforcer allows" do
      enforce = fn request ->
        request == %{
          tenant_id: "tenant_a",
          domain: "tenant_a",
          user_id: "user_123",
          subject: "user:user_123",
          action: "retrieve",
          resource_type: "document_chunk",
          resource_id: nil,
          object: "document_chunk:*"
        }
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

    test "builds object identifiers from resource ids and namespace options" do
      enforce = fn request ->
        request.subject == "member:user_123" and
          request.object == "doc:doc_456" and
          request.domain == "tenant_a"
      end

      target = %{
        policy_version: "policy_v12",
        subject_namespace: "member",
        object_namespace: "doc",
        enforce: enforce
      }

      assert {:ok, decision} =
               Authorizer.authorize({Casbin, target}, request_map(resource_id: "doc_456"))

      assert decision.decision == :allow
    end

    test "keeps the legacy four-argument enforcer port" do
      enforce = fn tenant_id, user_id, action, resource_type ->
        tenant_id == "tenant_a" and user_id == "user_123" and action == "retrieve" and
          resource_type == "document_chunk"
      end

      assert {:ok, %{decision: :allow}} =
               Authorizer.authorize(
                 {Casbin, %{policy_version: "policy_v12", enforce: enforce}},
                 request()
               )
    end

    test "denies without executing ABAC widening when Casbin denies" do
      enforce = fn _request -> false end

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
      assert Authorizer.authorize({Casbin, %{enforce: fn _request -> true end}}, request()) ==
               {:error, :invalid_policy_version}

      assert Authorizer.authorize({Casbin, %{policy_version: "policy_v12"}}, request()) ==
               {:error, :invalid_casbin_enforcer}

      assert Authorizer.authorize(
               {Casbin,
                %{
                  policy_version: "policy_v12",
                  enforce: fn _request -> :maybe end
                }},
               request()
             ) == {:error, :invalid_casbin_decision}

      assert Authorizer.authorize(
               {Casbin,
                %{
                  policy_version: "policy_v12",
                  enforce: fn _request -> raise "casbin unavailable" end
                }},
               request()
             ) == {:error, :casbin_enforcer_failed}

      assert Authorizer.authorize(
               {Casbin,
                %{
                  policy_version: "policy_v12",
                  roles: [""],
                  enforce: fn _request -> true end
                }},
               request()
             ) == {:error, :invalid_roles}

      assert Authorizer.authorize(
               {Casbin,
                %{
                  policy_version: "policy_v12",
                  timeout_ms: -1,
                  enforce: fn _request -> true end
                }},
               request()
             ) == {:error, :invalid_casbin_timeout}

      assert Authorizer.authorize(
               {Casbin,
                %{
                  policy_version: "policy_v12",
                  object_namespace: "",
                  enforce: fn _request -> true end
                }},
               request()
             ) == {:error, :invalid_object_namespace}
    end

    test "fails closed when the enforcer does not respond within the timeout" do
      enforce = fn _request ->
        receive do
          :continue -> true
        end
      end

      assert Authorizer.authorize(
               {Casbin, %{policy_version: "policy_v12", timeout_ms: 0, enforce: enforce}},
               request()
             ) == {:error, :casbin_enforcer_timeout}
    end
  end

  defp request(attrs \\ []), do: tool_call(attrs)

  defp request_map(attrs) do
    request()
    |> Map.from_struct()
    |> Map.merge(Map.new(attrs))
  end
end
