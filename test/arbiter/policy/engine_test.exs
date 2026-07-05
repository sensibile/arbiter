defmodule Arbiter.Policy.EngineTest do
  use ExUnit.Case, async: true

  alias Arbiter.Policy.Engine
  alias Arbiter.Policy.Parser

  @dsl """
  policy "contract_chunk_read" {
    allow user retrieve chunk
    when user.tenant_id == chunk.tenant_id
     and user.status == "active"
     and user.clearance_level >= chunk.sensitivity_level
     and chunk.department_id in user.department_ids
  }
  """

  test "evaluates policy DSL into a decision with request intent" do
    assert {:ok, decision} =
             Engine.evaluate(@dsl, context(),
               subject: "user",
               action: "retrieve",
               resource: "chunk",
               policy_version: "policy_v12"
             )

    assert decision.decision == :allow
    assert decision.policy_version == "policy_v12"

    assert decision.scope == %{
             "tenant_id" => "tenant_a",
             "departments" => ["finance"],
             "max_sensitivity" => 3
           }
  end

  test "evaluates parsed AST values without reparsing" do
    assert {:ok, ast} = Parser.parse(@dsl)

    assert {:ok, decision} =
             Engine.evaluate(ast, context(),
               subject: "user",
               action: "retrieve",
               resource: "chunk"
             )

    assert decision.decision == :allow
  end

  test "returns parse errors separately from deny decisions" do
    assert {:error, error} = Engine.evaluate("not a policy", context())
    assert error.reason == :invalid_policy

    assert {:ok, decision} =
             Engine.evaluate(@dsl, context(),
               subject: "user",
               action: "delete",
               resource: "chunk"
             )

    assert decision.decision == :deny
    assert decision.reason == ["policy_intent_mismatch"]
  end

  test "rejects malformed engine inputs" do
    assert Engine.evaluate(:not_a_policy, context()) == {:error, :invalid_policy_engine_input}
    assert Engine.evaluate(@dsl, :not_context) == {:error, :invalid_policy_engine_input}
  end

  defp context do
    %{
      user: %{
        tenant_id: "tenant_a",
        status: "active",
        clearance_level: 3,
        department_ids: ["finance"]
      },
      chunk: %{
        tenant_id: "tenant_a",
        sensitivity_level: 2,
        department_id: "finance"
      }
    }
  end
end
