defmodule Arbiter.Policy.ScopeCompileError do
  @moduledoc """
  Structured error returned when a policy scope cannot be compiled.
  """

  @enforce_keys [:reason, :message]
  defstruct [:reason, :message]
end
