defmodule Arbiter.Sync.RevokeSimulationTest do
  use Arbiter.DataCase, async: true

  alias Arbiter.Repo
  alias Arbiter.Sync.RevokeSimulation
  alias Arbiter.Tenants.Tenant
  alias Arbiter.Tenants.User
  alias Arbiter.Gateway
  alias Arbiter.Gateway.ToolCall
  alias Arbiter.Policy.Decision

  describe "revoke_user_access/2" do
    test "bumps user policy version and returns revoke-first invalidation commands" do
      %{tenant: tenant, user: user} = fixture_scope(policy_version: "policy_v12")

      assert {:ok, result} =
               RevokeSimulation.revoke_user_access(user,
                 reason: "removed_from_group",
                 source: "simulation"
               )

      reloaded_user = Repo.get!(User, user.id)

      assert reloaded_user.policy_version == "policy_v13"
      assert result.user.id == user.id
      assert result.previous_policy_version == "policy_v12"
      assert result.current_policy_version == "policy_v13"

      assert result.invalidation_commands == [
               %{
                 command: :invalidate_user_access_cache,
                 tenant_id: tenant.id,
                 user_id: user.id,
                 previous_policy_version: "policy_v12",
                 current_policy_version: "policy_v13"
               },
               %{
                 command: :invalidate_tool_result_cache,
                 tenant_id: tenant.id,
                 user_id: user.id,
                 previous_policy_version: "policy_v12",
                 current_policy_version: "policy_v13"
               },
               %{
                 command: :invalidate_retrieval_result_cache,
                 tenant_id: tenant.id,
                 user_id: user.id,
                 previous_policy_version: "policy_v12",
                 current_policy_version: "policy_v13"
               }
             ]

      assert result.audit_event == %{
               event_type: "access_revoked",
               tenant_id: tenant.id,
               user_id: user.id,
               reason: "removed_from_group",
               source: "simulation",
               previous_policy_version: "policy_v12",
               current_policy_version: "policy_v13",
               invalidation_commands: result.invalidation_commands
             }
    end

    test "does not update user when policy version cannot be incremented" do
      %{user: user} = fixture_scope(policy_version: "custom")

      assert {:error, :invalid_policy_version} = RevokeSimulation.revoke_user_access(user)

      reloaded_user = Repo.get!(User, user.id)
      assert reloaded_user.policy_version == "custom"
    end

    test "uses the latest persisted user policy version instead of a stale struct" do
      %{user: stale_user} = fixture_scope(policy_version: "policy_v12")

      stale_user
      |> User.changeset(%{policy_version: "policy_v15"})
      |> Repo.update!()

      assert {:ok, result} = RevokeSimulation.revoke_user_access(stale_user)

      assert result.previous_policy_version == "policy_v15"
      assert result.current_policy_version == "policy_v16"
      assert Repo.get!(User, stale_user.id).policy_version == "policy_v16"
    end

    test "old tool call snapshot is denied after revoke bumps policy version" do
      %{tenant: tenant, user: user} = fixture_scope(policy_version: "policy_v12")

      old_snapshot = %{
        "id" => user.id,
        "tenant_id" => tenant.id,
        "policy_version" => "policy_v12"
      }

      assert {:ok, %{current_policy_version: "policy_v13"}} =
               RevokeSimulation.revoke_user_access(user)

      execute = fn _guarded_query -> {:ok, []} end

      decision = %Decision{
        decision: :allow,
        reason: ["same_tenant"],
        policy_version: "policy_v13",
        scope: %{
          "tenant_id" => tenant.id,
          "departments" => ["finance"],
          "max_sensitivity" => 1
        }
      }

      tool_call = %ToolCall{
        tenant_id: tenant.id,
        user_id: user.id,
        agent_run_id: Ecto.UUID.generate(),
        tool: "semantic_search",
        action: "retrieve",
        resource_type: "document_chunk",
        query: %{"text" => "renewal risk"},
        user_snapshot: old_snapshot,
        resource_snapshot: %{"resource_type" => "document_chunk"}
      }

      assert {:error, error} =
               Gateway.run_tool_call(tool_call,
                 tools: tools(execute),
                 authorize: fn _tool_call -> {:ok, decision} end
               )

      assert error.reason == :stale_user_policy_version
      assert error.audit_event.reason == ["stale_user_policy_version"]
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

  defp fixture_scope(attrs) do
    tenant =
      %Tenant{}
      |> Tenant.changeset(%{name: "tenant-#{System.unique_integer([:positive])}"})
      |> Repo.insert!()

    user =
      %User{tenant_id: tenant.id}
      |> User.changeset(%{
        email: "user-#{System.unique_integer([:positive])}@example.com",
        role: "analyst",
        policy_version: Keyword.fetch!(attrs, :policy_version)
      })
      |> Repo.insert!()

    %{tenant: tenant, user: user}
  end
end
