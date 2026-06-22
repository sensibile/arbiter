defmodule Arbiter.Gateway.Error do
  @moduledoc """
  Fail-closed gateway error with audit event data.
  """

  @enforce_keys [:reason, :message, :audit_event]
  defstruct [:reason, :message, :audit_event]
end
