defmodule Arbiter.Policy.Decision do
  @moduledoc """
  Runtime policy decision returned by pure policy evaluation.
  """

  @enforce_keys [:decision, :reason, :policy_version, :scope]
  defstruct [:decision, :reason, :policy_version, :scope]
end
