defmodule Arbiter.Gateway.ToolCall do
  @moduledoc """
  Agent tool call request accepted by the Arbiter Gateway.

  The gateway owns authorization and retrieval enforcement. Boundary modules own
  loading users, policies, vector adapters, clocks, IDs, and audit persistence.
  """

  @enforce_keys [
    :tenant_id,
    :user_id,
    :agent_run_id,
    :tool,
    :action,
    :resource_type,
    :query,
    :user_snapshot,
    :resource_snapshot
  ]
  defstruct [
    :tenant_id,
    :user_id,
    :agent_run_id,
    :tool,
    :action,
    :resource_type,
    :resource_id,
    :query,
    :user_snapshot,
    :resource_snapshot
  ]
end
