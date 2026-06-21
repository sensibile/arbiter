defmodule Arbiter.Policy.ScopeCompilerTest do
  use ExUnit.Case, async: true

  alias Arbiter.Policy.Decision
  alias Arbiter.Policy.ScopeCompiler

  describe "to_sql_predicate/1" do
    test "compiles an allowed decision scope into a parameterized SQL predicate" do
      decision = allow_decision()

      assert {:ok, predicate} = ScopeCompiler.to_sql_predicate(decision)

      assert predicate.sql ==
               "tenant_id = $1 AND deleted_at IS NULL AND sensitivity_level <= $2 AND department_id = ANY($3)"

      assert predicate.params == ["tenant_a", 3, ["finance", "legal"]]
      assert predicate.scope == decision.scope
    end

    test "rejects deny decisions so callers can fail closed" do
      decision = %Decision{
        decision: :deny,
        reason: ["clearance_ok_failed"],
        policy_version: "policy_v12",
        scope: %{}
      }

      assert {:error, error} = ScopeCompiler.to_sql_predicate(decision)
      assert error.reason == :decision_not_allowed
    end

    test "rejects scopes missing required values" do
      decision = %Decision{
        decision: :allow,
        reason: ["same_tenant"],
        policy_version: "policy_v12",
        scope: %{"tenant_id" => "tenant_a"}
      }

      assert {:error, error} = ScopeCompiler.to_sql_predicate(decision)
      assert error.reason == :invalid_scope
    end

    test "rejects non-decision inputs" do
      assert {:error, error} = ScopeCompiler.to_sql_predicate(%{})
      assert error.reason == :invalid_decision
    end
  end

  describe "to_vector_filter/1" do
    test "compiles an allowed decision scope into a vector metadata filter" do
      decision = allow_decision()

      assert {:ok, filter} = ScopeCompiler.to_vector_filter(decision)

      assert filter == %{
               "tenant_id" => "tenant_a",
               "visibility" => %{"$in" => ["public", "department"]},
               "department_id" => %{"$in" => ["finance", "legal"]},
               "sensitivity_level" => %{"$lte" => 3},
               "deleted" => false
             }
    end

    test "rejects invalid department values" do
      decision =
        allow_decision(%{
          "tenant_id" => "tenant_a",
          "departments" => [],
          "max_sensitivity" => 3
        })

      assert {:error, error} = ScopeCompiler.to_vector_filter(decision)
      assert error.reason == :invalid_scope
    end

    test "rejects non-decision inputs" do
      assert {:error, error} = ScopeCompiler.to_vector_filter(%{})
      assert error.reason == :invalid_decision
    end
  end

  defp allow_decision(scope \\ default_scope()) do
    %Decision{
      decision: :allow,
      reason: [
        "same_tenant",
        "active_user",
        "source_matched",
        "clearance_ok",
        "department_scope_matched"
      ],
      policy_version: "policy_v12",
      scope: scope
    }
  end

  defp default_scope do
    %{
      "tenant_id" => "tenant_a",
      "departments" => ["finance", "legal"],
      "max_sensitivity" => 3
    }
  end
end
