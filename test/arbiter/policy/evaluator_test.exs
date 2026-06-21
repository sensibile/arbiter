defmodule Arbiter.Policy.EvaluatorTest do
  use ExUnit.Case, async: true

  alias Arbiter.Policy.AST
  alias Arbiter.Policy.Evaluator
  alias Arbiter.Policy.Parser
  alias Arbiter.Tenants.User

  @dsl """
  policy "contract_chunk_read" {
    allow user retrieve chunk
    when user.tenant_id == chunk.tenant_id
     and user.status == "active"
     and chunk.source == "contracts"
     and user.clearance_level >= chunk.sensitivity_level
     and chunk.department_id in user.department_ids
  }
  """

  setup do
    {:ok, ast} = Parser.parse(@dsl)

    user = %User{
      tenant_id: "tenant_a",
      status: "active",
      clearance_level: 3,
      department_ids: ["finance", "legal"],
      policy_version: "policy_v12"
    }

    chunk = %{
      tenant_id: "tenant_a",
      source: "contracts",
      sensitivity_level: 2,
      department_id: "finance",
      policy_version: "policy_v12"
    }

    {:ok, ast: ast, user: user, chunk: chunk}
  end

  test "allows when every DSL condition is satisfied", %{ast: ast, user: user, chunk: chunk} do
    decision = Evaluator.evaluate(ast, %{user: user, chunk: chunk}, policy_version: "policy_v12")

    assert decision.decision == :allow
    assert decision.policy_version == "policy_v12"

    assert decision.reason == [
             "same_tenant",
             "active_user",
             "source_matched",
             "clearance_ok",
             "department_scope_matched"
           ]

    assert decision.scope == %{
             "tenant_id" => "tenant_a",
             "departments" => ["finance", "legal"],
             "max_sensitivity" => 3
           }
  end

  test "denies when a condition fails", %{ast: ast, user: user, chunk: chunk} do
    denied_chunk = %{chunk | sensitivity_level: 5}

    decision = Evaluator.evaluate(ast, %{user: user, chunk: denied_chunk})

    assert decision.decision == :deny
    assert decision.reason == ["clearance_ok_failed"]
    assert decision.scope == %{}
  end

  test "fails closed when required attributes are missing", %{ast: ast, chunk: chunk} do
    decision = Evaluator.evaluate(ast, %{user: %{tenant_id: "tenant_a"}, chunk: chunk})

    assert decision.decision == :deny
    assert decision.reason == ["evaluation_error"]
    assert decision.scope == %{}
  end

  test "fails closed when conditions pass but scope cannot be built" do
    ast = %AST{
      name: "scope_required",
      effect: :allow,
      subject: "user",
      action: "retrieve",
      resource: "chunk",
      conditions: [
        %{
          left: {:path, "user", ["tenant_id"]},
          operator: :eq,
          right: {:path, "chunk", ["tenant_id"]},
          reason: "same_tenant"
        }
      ]
    }

    decision =
      Evaluator.evaluate(ast, %{user: %{tenant_id: "tenant_a"}, chunk: %{tenant_id: "tenant_a"}})

    assert decision.decision == :deny
    assert decision.reason == ["scope_compile_failed"]
    assert decision.scope == %{}
  end

  test "supports map contexts as well as structs", %{ast: ast} do
    user = %{
      tenant_id: "tenant_a",
      status: "active",
      clearance_level: 3,
      department_ids: ["finance"]
    }

    chunk = %{
      tenant_id: "tenant_a",
      source: "contracts",
      sensitivity_level: 3,
      department_id: "finance"
    }

    assert %{decision: :allow} = Evaluator.evaluate(ast, %{user: user, chunk: chunk})
  end

  test "supports the minimal comparison operator set" do
    ast = %AST{
      name: "operator_policy",
      effect: :allow,
      subject: "user",
      action: "retrieve",
      resource: "chunk",
      conditions: [
        %{
          left: {:path, "user", ["role"]},
          operator: :neq,
          right: {:literal, "suspended"},
          reason: "role_not_suspended"
        },
        %{
          left: {:path, "chunk", ["sensitivity_level"]},
          operator: :lte,
          right: {:path, "user", ["clearance_level"]},
          reason: "sensitivity_within_clearance"
        },
        %{
          left: {:path, "user", ["clearance_level"]},
          operator: :gt,
          right: {:literal, 0},
          reason: "has_clearance"
        },
        %{
          left: {:path, "chunk", ["sensitivity_level"]},
          operator: :lt,
          right: {:literal, 5},
          reason: "not_highly_sensitive"
        }
      ]
    }

    user = %{
      tenant_id: "tenant_a",
      department_ids: ["finance"],
      clearance_level: 3,
      role: "reader"
    }

    chunk = %{sensitivity_level: 2}

    assert %{decision: :allow} = Evaluator.evaluate(ast, %{user: user, chunk: chunk})
  end

  test "fails closed for unsupported comparison types" do
    ast = %AST{
      name: "bad_comparison",
      effect: :allow,
      subject: "user",
      action: "retrieve",
      resource: "chunk",
      conditions: [
        %{
          left: {:path, "user", ["clearance_level"]},
          operator: :gte,
          right: {:literal, "high"},
          reason: "clearance_ok"
        }
      ]
    }

    decision = Evaluator.evaluate(ast, %{user: %{clearance_level: 3}, chunk: %{}})

    assert decision.decision == :deny
    assert decision.reason == ["evaluation_error"]
  end

  test "fails closed for unsupported ASTs" do
    assert %{decision: :deny, reason: ["evaluation_error"]} = Evaluator.evaluate(:not_an_ast, %{})
  end
end
