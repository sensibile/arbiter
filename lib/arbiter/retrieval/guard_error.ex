defmodule Arbiter.Retrieval.GuardError do
  @moduledoc """
  Structured error returned when retrieval guard input is invalid.
  """

  @enforce_keys [:reason, :message]
  defstruct [:reason, :message]
end
