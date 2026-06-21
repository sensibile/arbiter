defmodule Arbiter.Policy.ScopeCompiler do
  @moduledoc """
  Compiles policy decision scopes into query-layer filters.

  This module is intentionally pure. It does not call Repo, vector stores, or
  external services.
  """

  alias Arbiter.Policy.Decision
  alias Arbiter.Policy.ScopeCompileError
  alias Arbiter.Policy.SQLPredicate

  @sql_template "tenant_id = $1 AND deleted_at IS NULL AND sensitivity_level <= $2 AND department_id = ANY($3)"
  @default_visibility ["public", "department"]

  def to_sql_predicate(%Decision{decision: :allow, scope: scope}) do
    with {:ok, normalized_scope} <- normalize_scope(scope) do
      {:ok,
       %SQLPredicate{
         sql: @sql_template,
         params: [
           normalized_scope.tenant_id,
           normalized_scope.max_sensitivity,
           normalized_scope.departments
         ],
         scope: scope
       }}
    end
  end

  def to_sql_predicate(%Decision{}) do
    {:error,
     error(
       :decision_not_allowed,
       "cannot compile a query predicate for a non-allow policy decision"
     )}
  end

  def to_sql_predicate(_decision),
    do: {:error, error(:invalid_decision, "expected a policy decision")}

  def to_vector_filter(%Decision{decision: :allow, scope: scope}) do
    with {:ok, normalized_scope} <- normalize_scope(scope) do
      {:ok,
       %{
         "tenant_id" => normalized_scope.tenant_id,
         "visibility" => %{"$in" => @default_visibility},
         "department_id" => %{"$in" => normalized_scope.departments},
         "sensitivity_level" => %{"$lte" => normalized_scope.max_sensitivity},
         "deleted" => false
       }}
    end
  end

  def to_vector_filter(%Decision{}) do
    {:error,
     error(
       :decision_not_allowed,
       "cannot compile a vector filter for a non-allow policy decision"
     )}
  end

  def to_vector_filter(_decision),
    do: {:error, error(:invalid_decision, "expected a policy decision")}

  defp normalize_scope(scope) when is_map(scope) do
    tenant_id = Map.get(scope, "tenant_id")
    departments = Map.get(scope, "departments")
    max_sensitivity = Map.get(scope, "max_sensitivity")

    if valid_scope?(tenant_id, departments, max_sensitivity) do
      {:ok,
       %{
         tenant_id: tenant_id,
         departments: departments,
         max_sensitivity: max_sensitivity
       }}
    else
      {:error,
       error(
         :invalid_scope,
         "scope requires tenant_id, non-empty departments, and non-negative max_sensitivity"
       )}
    end
  end

  defp normalize_scope(_scope), do: {:error, error(:invalid_scope, "scope must be a map")}

  defp valid_scope?(tenant_id, departments, max_sensitivity) do
    is_binary(tenant_id) and tenant_id != "" and
      is_list(departments) and departments != [] and Enum.all?(departments, &valid_department?/1) and
      is_integer(max_sensitivity) and max_sensitivity >= 0
  end

  defp valid_department?(department), do: is_binary(department) and department != ""

  defp error(reason, message), do: %ScopeCompileError{reason: reason, message: message}
end
