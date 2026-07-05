defmodule Arbiter.Retrieval.GuardedQuery do
  @moduledoc """
  Vector retrieval request after Arbiter has forced an authorization filter.
  """

  @enforce_keys [:query, :applied_filter, :policy_version]
  defstruct [:query, :applied_filter, :policy_version, allowed_chunk_ids: nil]

  @type t :: %__MODULE__{
          query: map(),
          applied_filter: map(),
          policy_version: String.t(),
          allowed_chunk_ids: [String.t()] | nil
        }
end
