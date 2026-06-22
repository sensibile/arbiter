defmodule Arbiter.Gateway.Result do
  @moduledoc """
  Result returned by a gateway-authorized tool call.
  """

  @enforce_keys [
    :tool_call,
    :policy_decision,
    :allowed_chunks,
    :rejected_chunk_ids,
    :audit_event
  ]
  defstruct [
    :tool_call,
    :policy_decision,
    :allowed_chunks,
    :rejected_chunk_ids,
    :audit_event
  ]
end
