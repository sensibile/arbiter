defmodule Arbiter.Policy.ParserTest do
  use ExUnit.Case, async: true

  alias Arbiter.Policy.Parser

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

  test "parses the minimal policy DSL into an AST" do
    assert {:ok, ast} = Parser.parse(@dsl)

    assert ast.name == "contract_chunk_read"
    assert ast.effect == :allow
    assert ast.subject == "user"
    assert ast.action == "retrieve"
    assert ast.resource == "chunk"

    assert [
             %{
               left: {:path, "user", ["tenant_id"]},
               operator: :eq,
               right: {:path, "chunk", ["tenant_id"]},
               reason: "same_tenant"
             },
             %{
               left: {:path, "user", ["status"]},
               operator: :eq,
               right: {:literal, "active"},
               reason: "active_user"
             },
             %{
               left: {:path, "chunk", ["source"]},
               operator: :eq,
               right: {:literal, "contracts"},
               reason: "source_matched"
             },
             %{
               left: {:path, "user", ["clearance_level"]},
               operator: :gte,
               right: {:path, "chunk", ["sensitivity_level"]},
               reason: "clearance_ok"
             },
             %{
               left: {:path, "chunk", ["department_id"]},
               operator: :in,
               right: {:path, "user", ["department_ids"]},
               reason: "department_scope_matched"
             }
           ] = ast.conditions
  end

  test "returns an error for unsupported DSL" do
    assert {:error, error} = Parser.parse("not a policy")
    assert error.reason == :invalid_policy
  end

  test "requires at least one condition" do
    dsl = """
    policy "empty" {
      allow user retrieve chunk
    }
    """

    assert {:error, error} = Parser.parse(dsl)
    assert error.reason == :missing_conditions
  end

  test "rejects unsupported operands" do
    dsl = """
    policy "bad_operand" {
      allow user retrieve chunk
      when user.status == active
    }
    """

    assert {:error, error} = Parser.parse(dsl)
    assert error.reason == :invalid_operand
  end

  test "parses boolean and integer literals" do
    dsl = """
    policy "literal_policy" {
      allow user retrieve chunk
      when user.clearance_level >= 2
       and chunk.deleted_at == false
    }
    """

    assert {:ok, ast} = Parser.parse(dsl)

    assert [
             %{operator: :gte, right: {:literal, 2}},
             %{operator: :eq, right: {:literal, false}}
           ] = ast.conditions
  end
end
