defmodule Arbiter.ReadModels.AccessibleDocumentChunkBuilderTest do
  use ExUnit.Case, async: true

  alias Arbiter.Policy.Decision
  alias Arbiter.ReadModels.AccessibleDocumentChunkBuilder

  @projected_at ~U[2026-06-24 12:00:00Z]

  describe "build/4" do
    test "builds projection attrs for chunks matching an allow decision" do
      assert {:ok, attrs} =
               AccessibleDocumentChunkBuilder.build(
                 user(),
                 chunk(),
                 allow_decision(),
                 @projected_at
               )

      assert attrs == %{
               tenant_id: "tenant_a",
               user_id: "user_1",
               chunk_id: "chunk_1",
               document_id: "doc_1",
               user_policy_version: "policy_v12",
               chunk_policy_version: "policy_v12",
               chunk_deleted_at: nil,
               access_reason: [
                 "same_tenant",
                 "active_user",
                 "clearance_ok",
                 "department_scope_matched"
               ],
               projected_at: @projected_at,
               invalidated_at: nil
             }
    end

    test "does not build projection attrs for deny decisions" do
      decision = %Decision{
        decision: :deny,
        reason: ["rbac_denied"],
        policy_version: "policy_v12",
        scope: %{}
      }

      assert AccessibleDocumentChunkBuilder.build(user(), chunk(), decision, @projected_at) ==
               {:error, :decision_not_allowed}
    end

    test "fails closed when an allow decision has an invalid scope" do
      decision =
        allow_decision(%{"tenant_id" => "tenant_a", "departments" => [], "max_sensitivity" => 3})

      assert AccessibleDocumentChunkBuilder.build(user(), chunk(), decision, @projected_at) ==
               {:error, :invalid_scope}
    end

    test "fails closed when user and chunk tenants differ" do
      assert AccessibleDocumentChunkBuilder.build(
               user(),
               chunk(tenant_id: "tenant_b"),
               allow_decision(),
               @projected_at
             ) ==
               {:error, :tenant_mismatch}
    end

    test "fails closed when chunk tenant is outside the decision scope" do
      decision =
        allow_decision(%{
          "tenant_id" => "tenant_b",
          "departments" => ["finance"],
          "max_sensitivity" => 3
        })

      assert AccessibleDocumentChunkBuilder.build(user(), chunk(), decision, @projected_at) ==
               {:error, :outside_tenant_scope}
    end

    test "fails closed for chunks outside compiled scope" do
      assert AccessibleDocumentChunkBuilder.build(
               user(),
               chunk(department_id: "sales"),
               allow_decision(),
               @projected_at
             ) ==
               {:error, :outside_department_scope}

      assert AccessibleDocumentChunkBuilder.build(
               user(),
               chunk(sensitivity_level: 9),
               allow_decision(),
               @projected_at
             ) ==
               {:error, :outside_sensitivity_scope}
    end

    test "fails closed for deleted or stale chunks" do
      assert AccessibleDocumentChunkBuilder.build(
               user(),
               chunk(deleted_at: ~U[2026-06-24 00:00:00Z]),
               allow_decision(),
               @projected_at
             ) == {:error, :chunk_deleted}

      assert AccessibleDocumentChunkBuilder.build(
               user(),
               chunk(policy_version: "policy_v11"),
               allow_decision(),
               @projected_at
             ) ==
               {:error, :stale_chunk_policy_version}
    end

    test "fails closed for stale users and malformed input" do
      assert AccessibleDocumentChunkBuilder.build(
               user(policy_version: "policy_v11"),
               chunk(),
               allow_decision(),
               @projected_at
             ) ==
               {:error, :stale_user_policy_version}

      assert AccessibleDocumentChunkBuilder.build(
               user(),
               %{id: "chunk_1"},
               allow_decision(),
               @projected_at
             ) ==
               {:error, :missing_document_id}

      assert AccessibleDocumentChunkBuilder.build(
               user(id: ""),
               chunk(),
               allow_decision(),
               @projected_at
             ) == {:error, :invalid_id}

      assert AccessibleDocumentChunkBuilder.build(
               user(),
               chunk(sensitivity_level: "high"),
               allow_decision(),
               @projected_at
             ) == {:error, :invalid_sensitivity_level}

      assert AccessibleDocumentChunkBuilder.build(
               user(),
               Map.delete(chunk(), :sensitivity_level),
               allow_decision(),
               @projected_at
             ) == {:error, :missing_sensitivity_level}

      assert AccessibleDocumentChunkBuilder.build(
               user(),
               Map.delete(chunk(), :deleted_at),
               allow_decision(),
               @projected_at
             ) == {:error, :missing_deleted_at}

      assert AccessibleDocumentChunkBuilder.build(
               user(),
               chunk(),
               allow_decision(),
               "not-a-datetime"
             ) ==
               {:error, :invalid_projection_input}
    end
  end

  defp allow_decision(
         scope \\ %{
           "tenant_id" => "tenant_a",
           "departments" => ["finance", "legal"],
           "max_sensitivity" => 3
         }
       ) do
    %Decision{
      decision: :allow,
      reason: ["same_tenant", "active_user", "clearance_ok", "department_scope_matched"],
      policy_version: "policy_v12",
      scope: scope
    }
  end

  defp user(attrs \\ []) do
    attrs
    |> Keyword.put_new(:id, "user_1")
    |> Keyword.put_new(:tenant_id, "tenant_a")
    |> Keyword.put_new(:policy_version, "policy_v12")
    |> Map.new()
  end

  defp chunk(attrs \\ []) do
    attrs
    |> Keyword.put_new(:id, "chunk_1")
    |> Keyword.put_new(:document_id, "doc_1")
    |> Keyword.put_new(:tenant_id, "tenant_a")
    |> Keyword.put_new(:department_id, "finance")
    |> Keyword.put_new(:sensitivity_level, 2)
    |> Keyword.put_new(:deleted_at, nil)
    |> Keyword.put_new(:policy_version, "policy_v12")
    |> Map.new()
  end
end
