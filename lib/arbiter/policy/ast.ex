defmodule Arbiter.Policy.AST do
  @moduledoc """
  Parsed representation of the minimal Arbiter policy DSL.
  """

  @enforce_keys [:name, :effect, :subject, :action, :resource, :conditions]
  defstruct [:name, :effect, :subject, :action, :resource, :conditions]
end
