defmodule Arbiter.Policy.Decision do
  @moduledoc """
  Runtime policy decision returned by pure policy evaluation.
  """

  @enforce_keys [:decision, :reason, :policy_version, :scope]
  defstruct [:decision, :reason, :policy_version, :scope]

  @type t :: %__MODULE__{
          decision: :allow | :deny,
          reason: [String.t()],
          policy_version: String.t(),
          scope: map()
        }
end
