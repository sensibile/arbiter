defmodule Arbiter.Authorizers.RepoBackedTest do
  use Arbiter.DataCase, async: false

  alias Arbiter.Authorizers.RepoBacked
  alias Arbiter.Gateway.ToolCall
  alias Arbiter.Policy.Authorizer
  alias Arbiter.Repo
  alias Arbiter.Tenants.User

  import Arbiter.DomainFixtures

  setup_all do
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)
    Ecto.Migrator.run(Repo, :up, all: true)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :manual)
    :ok
  end

  describe "authorize/2" do
    test "loads current user role and ABAC scope from Repo" do
      tenant = tenant_fixture("repo-authz")

      user =
        user_fixture(tenant,
          role: "analyst",
          department_ids: ["finance", "legal"],
          clearance_level: 3,
          policy_version: "policy_v12"
        )

      assert {:ok, decision} =
               Authorizer.authorize(
                 {RepoBacked, %{permissions: permissions(tenant.id)}},
                 request(tenant, user)
               )

      assert decision.decision == :allow
      assert decision.policy_version == "policy_v12"

      assert decision.scope == %{
               "tenant_id" => tenant.id,
               "departments" => ["finance", "legal"],
               "max_sensitivity" => 3,
               "roles" => ["analyst"]
             }
    end

    test "denies inactive persisted users without granting scope" do
      tenant = tenant_fixture("repo-authz-inactive")

      user =
        user_fixture(tenant,
          status: "inactive",
          role: "analyst",
          department_ids: ["finance"],
          clearance_level: 3,
          policy_version: "policy_v12"
        )

      assert {:ok, decision} =
               Authorizer.authorize(
                 {RepoBacked, %{permissions: permissions(tenant.id)}},
                 request(tenant, user)
               )

      assert decision.decision == :deny
      assert decision.reason == ["inactive_user"]
      assert decision.policy_version == "policy_v12"
      assert decision.scope == %{}
    end

    test "fails closed when request snapshot is stale against Repo state" do
      tenant = tenant_fixture("repo-authz-stale")

      user =
        user_fixture(tenant,
          role: "analyst",
          department_ids: ["finance"],
          clearance_level: 3,
          policy_version: "policy_v12"
        )

      assert Authorizer.authorize(
               {RepoBacked, %{permissions: permissions(tenant.id)}},
               request(tenant, user, policy_version: "policy_v11")
             ) == {:error, :stale_user_policy_version}

      assert {:ok, user} =
               user
               |> User.changeset(%{department_ids: ["legal"]})
               |> Repo.update()

      assert Authorizer.authorize(
               {RepoBacked, %{permissions: permissions(tenant.id)}},
               request(tenant, user, department_ids: ["finance"])
             ) == {:error, :stale_user_departments}

      assert {:ok, user} =
               user
               |> User.changeset(%{department_ids: ["finance"], clearance_level: 2})
               |> Repo.update()

      assert Authorizer.authorize(
               {RepoBacked, %{permissions: permissions(tenant.id)}},
               request(tenant, user, clearance_level: 3)
             ) == {:error, :stale_user_clearance}
    end

    test "fails closed for missing users and malformed targets" do
      tenant = tenant_fixture("repo-authz-missing")
      user = user_fixture(tenant, policy_version: "policy_v12")

      missing_user = %{user | id: Ecto.UUID.generate()}

      assert Authorizer.authorize(
               {RepoBacked, %{permissions: permissions(tenant.id)}},
               request(tenant, missing_user)
             ) == {:error, :user_not_found}

      assert Authorizer.authorize({RepoBacked, %{}}, request(tenant, user)) ==
               {:error, :invalid_permissions}

      assert Authorizer.authorize(
               {RepoBacked, %{repo: "not_a_repo", permissions: permissions(tenant.id)}},
               request(tenant, user)
             ) == {:error, :invalid_repo}
    end

    test "fails closed when the request omits the current policy version" do
      tenant = tenant_fixture("repo-authz-missing-policy-version")
      user = user_fixture(tenant, policy_version: "policy_v12")

      assert Authorizer.authorize(
               {RepoBacked, %{permissions: permissions(tenant.id)}},
               request(tenant, user, policy_version: nil)
             ) == {:error, :missing_user_policy_version}
    end

    test "denies when the persisted role has no matching permission" do
      tenant = tenant_fixture("repo-authz-rbac-deny")

      user =
        user_fixture(tenant,
          role: "viewer",
          department_ids: ["finance"],
          clearance_level: 3,
          policy_version: "policy_v12"
        )

      assert {:ok, decision} =
               Authorizer.authorize(
                 {RepoBacked, %{permissions: permissions(tenant.id)}},
                 request(tenant, user)
               )

      assert decision.decision == :deny
      assert decision.reason == ["rbac_denied"]
      assert decision.policy_version == "policy_v12"
      assert decision.scope == %{}
    end
  end

  defp permissions(tenant_id) do
    [
      %{
        role: "analyst",
        action: "retrieve",
        resource_type: "document_chunk",
        tenant_id: tenant_id
      }
    ]
  end

  defp request(tenant, user, attrs \\ []) do
    snapshot = %{
      "id" => user.id,
      "tenant_id" => tenant.id,
      "department_ids" => Keyword.get(attrs, :department_ids, user.department_ids),
      "clearance_level" => Keyword.get(attrs, :clearance_level, user.clearance_level),
      "policy_version" => Keyword.get(attrs, :policy_version, user.policy_version)
    }

    defaults = %{
      tenant_id: tenant.id,
      user_id: user.id,
      agent_run_id: Ecto.UUID.generate(),
      tool: "semantic_search",
      action: "retrieve",
      resource_type: "document_chunk",
      query: %{"text" => "renewal risk"},
      user_snapshot: snapshot,
      resource_snapshot: %{"resource_type" => "document_chunk"}
    }

    tool_call_attrs =
      attrs
      |> Keyword.drop([:department_ids, :clearance_level, :policy_version])
      |> Map.new()

    struct!(ToolCall, Map.merge(defaults, tool_call_attrs))
  end
end
