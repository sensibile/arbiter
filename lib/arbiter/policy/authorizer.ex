defmodule Arbiter.Policy.Authorizer do
  @moduledoc """
  Authorizer contract for turning Gateway requests into policy decisions.

  Authorizers receive already-loaded request and identity data. They do not own
  Repo access, external policy engines, clocks, IDs, or audit persistence.
  """

  alias Arbiter.Policy.Decision

  @callback authorize(target :: term(), request :: map()) ::
              {:ok, Decision.t()} | {:error, term()}

  def authorize({authorizer, target}, request) when is_atom(authorizer) and is_map(request) do
    authorizer.authorize(target, request)
  end

  def authorize({_authorizer, _target}, _request), do: {:error, :invalid_authorization_request}
  def authorize(_authorizer, _request), do: {:error, :invalid_authorizer}

  def executor(authorizer) do
    fn request -> authorize(authorizer, request) end
  end
end
