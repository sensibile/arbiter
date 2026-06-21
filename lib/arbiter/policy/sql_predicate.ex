defmodule Arbiter.Policy.SQLPredicate do
  @moduledoc """
  Parameterized SQL predicate compiled from an allowed policy scope.
  """

  @enforce_keys [:sql, :params, :scope]
  defstruct [:sql, :params, :scope]
end
