defmodule Arbiter.Retrieval.GuardTest do
  use ExUnit.Case, async: true

  alias Arbiter.Policy.Decision
  alias Arbiter.Retrieval.Guard

  describe "guard_vector_query/2" do
    test "forces the Arbiter metadata filter before top-k retrieval" do
      query = %{
        "text" => "renewal risk",
        "top_k" => 5,
        "filter" => %{"tenant_id" => "tenant_b"}
      }

      assert {:ok, guarded_query} = Guard.guard_vector_query(query, allow_decision())

      assert guarded_query.query == %{"text" => "renewal risk", "top_k" => 5}

      assert guarded_query.applied_filter == %{
               "tenant_id" => "tenant_a",
               "visibility" => %{"$in" => ["public", "department"]},
               "department_id" => %{"$in" => ["finance", "legal"]},
               "sensitivity_level" => %{"$lte" => 3},
               "deleted_at" => nil
             }

      assert guarded_query.policy_version == "policy_v12"
    end

    test "fails closed when the policy decision cannot produce a filter" do
      decision = %Decision{
        decision: :deny,
        reason: ["rbac_denied"],
        policy_version: "policy_v12",
        scope: %{}
      }

      assert {:error, error} = Guard.guard_vector_query(%{"text" => "renewal risk"}, decision)
      assert error.reason == :decision_not_allowed
    end

    test "fails closed for invalid query input" do
      assert {:error, error} = Guard.guard_vector_query("renewal risk", allow_decision())
      assert error.reason == :invalid_query
    end
  end

  describe "post_validate/2" do
    test "accepts only chunks still matching the compiled policy scope" do
      chunks = [
        chunk("chunk_1", tenant_id: "tenant_a", department_id: "finance", sensitivity_level: 2),
        chunk("chunk_2", tenant_id: "tenant_b", department_id: "finance", sensitivity_level: 2),
        chunk("chunk_3", tenant_id: "tenant_a", department_id: "sales", sensitivity_level: 2),
        chunk("chunk_4", tenant_id: "tenant_a", department_id: "legal", sensitivity_level: 5),
        chunk("chunk_5",
          tenant_id: "tenant_a",
          department_id: "legal",
          sensitivity_level: 1,
          deleted_at: ~U[2026-06-21 00:00:00Z]
        ),
        chunk("chunk_6",
          tenant_id: "tenant_a",
          department_id: "legal",
          sensitivity_level: 1,
          policy_version: "policy_v11"
        )
      ]

      assert {:ok, result} = Guard.post_validate(chunks, allow_decision())

      assert result.retrieved_chunk_ids == [
               "chunk_1",
               "chunk_2",
               "chunk_3",
               "chunk_4",
               "chunk_5",
               "chunk_6"
             ]

      assert result.accepted_chunk_ids == ["chunk_1"]
      assert result.rejected_chunk_ids == ["chunk_2", "chunk_3", "chunk_4", "chunk_5", "chunk_6"]
      assert Enum.map(result.accepted_chunks, & &1.id) == ["chunk_1"]

      assert Enum.map(result.rejected_chunks, & &1.id) == [
               "chunk_2",
               "chunk_3",
               "chunk_4",
               "chunk_5",
               "chunk_6"
             ]

      assert result.applied_filter["tenant_id"] == "tenant_a"
      assert result.policy_version == "policy_v12"
    end

    test "supports string-key chunk maps" do
      chunks = [
        %{
          "id" => "chunk_1",
          "tenant_id" => "tenant_a",
          "department_id" => "finance",
          "sensitivity_level" => 2,
          "deleted_at" => nil,
          "policy_version" => "policy_v12"
        }
      ]

      assert {:ok, result} = Guard.post_validate(chunks, allow_decision())
      assert result.accepted_chunk_ids == ["chunk_1"]
      assert result.rejected_chunk_ids == []
    end

    test "fails closed when chunks are missing required metadata" do
      chunks = [%{id: "chunk_1", tenant_id: "tenant_a"}]

      assert {:ok, result} = Guard.post_validate(chunks, allow_decision())

      assert result.accepted_chunk_ids == []
      assert result.rejected_chunk_ids == ["chunk_1"]
    end

    test "fails closed for invalid chunk input" do
      assert {:error, error} = Guard.post_validate(%{}, allow_decision())
      assert error.reason == :invalid_chunks
    end
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
