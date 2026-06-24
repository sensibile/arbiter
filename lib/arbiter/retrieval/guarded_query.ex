defmodule Arbiter.Retrieval.GuardedQuery do
  @moduledoc """
  Vector retrieval request after Arbiter has forced an authorization filter.
  """

  @enforce_keys [:query, :applied_filter, :policy_version]
  defstruct [:query, :applied_filter, :policy_version, allowed_chunk_ids: nil]
end
