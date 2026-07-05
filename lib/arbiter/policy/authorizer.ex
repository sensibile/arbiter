defmodule Arbiter.Policy.Authorizer do
  @moduledoc """
  Authorizer contract for turning Gateway requests into policy decisions.

  Authorizers receive already-loaded request and identity data. They do not own
  Repo access, external policy engines, clocks, IDs, or audit persistence.
  """

  alias Arbiter.Policy.{AuthorizationRequest, Decision}

  @type request :: AuthorizationRequest.t() | map()

  @callback authorize(target :: term(), request :: request()) ::
              {:ok, Decision.t()} | {:error, term()}

  def authorize({authorizer, target}, request) when is_atom(authorizer) do
    with {:ok, request} <- AuthorizationRequest.normalize(request) do
      if Code.ensure_loaded?(authorizer) and function_exported?(authorizer, :authorize, 2) do
        authorizer.authorize(target, request)
      else
        {:error, :invalid_authorizer}
      end
    end
  end

  def authorize({_authorizer, _target}, _request), do: {:error, :invalid_authorization_request}
  def authorize(_authorizer, _request), do: {:error, :invalid_authorizer}

  def executor(authorizer) do
    fn request -> authorize(authorizer, request) end
  end
end
