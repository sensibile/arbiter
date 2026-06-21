defmodule Arbiter.Retrieval.GuardResult do
  @moduledoc """
  Post-retrieval validation result used to build retrieval trace data.
  """

  @enforce_keys [
    :retrieved_chunks,
    :accepted_chunks,
    :rejected_chunks,
    :retrieved_chunk_ids,
    :accepted_chunk_ids,
    :rejected_chunk_ids,
    :applied_filter,
    :policy_version
  ]
  defstruct [
    :retrieved_chunks,
    :accepted_chunks,
    :rejected_chunks,
    :retrieved_chunk_ids,
    :accepted_chunk_ids,
    :rejected_chunk_ids,
    :applied_filter,
    :policy_version
  ]
end
