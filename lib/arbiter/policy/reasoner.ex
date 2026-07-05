defmodule Arbiter.Policy.Reasoner do
  @moduledoc """
  Derives stable decision reason identifiers for parsed policy conditions.

  The MVP still infers reasons from well-known condition shapes. Keeping this
  separate from parsing makes it easier to replace with explicit DSL reason IDs
  later without changing parser flow.
  """

  alias Arbiter.Policy.DecisionReason

  def infer({:path, "user", ["tenant_id"]}, :eq, {:path, "chunk", ["tenant_id"]}) do
    DecisionReason.same_tenant()
  end

  def infer({:path, "user", ["status"]}, :eq, {:literal, "active"}) do
    DecisionReason.active_user()
  end

  def infer({:path, "chunk", ["source"]}, :eq, {:literal, _source}) do
    DecisionReason.source_matched()
  end

  def infer(
        {:path, "user", ["clearance_level"]},
        :gte,
        {:path, "chunk", ["sensitivity_level"]}
      ) do
    DecisionReason.clearance_ok()
  end

  def infer({:path, "chunk", ["department_id"]}, :in, {:path, "user", ["department_ids"]}) do
    DecisionReason.department_scope_matched()
  end

  def infer(left, operator, right) do
    "#{operand_name(left)}_#{operator}_#{operand_name(right)}"
  end

  defp operand_name({:path, root, path}), do: Enum.join([root | path], "_")
  defp operand_name({:literal, value}), do: "literal_#{value}"
end
