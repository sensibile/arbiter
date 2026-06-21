defmodule Arbiter.Policy.ParseError do
  @moduledoc """
  Structured parse error for the minimal policy DSL.
  """

  @enforce_keys [:reason, :message]
  defstruct [:reason, :message, :line]
end
