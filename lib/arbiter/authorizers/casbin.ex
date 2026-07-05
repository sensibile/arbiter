defmodule Arbiter.Authorizers.Casbin do
  @moduledoc """
  Casbin-backed authorizer shell.

  This module keeps Arbiter's authorizer contract independent from a concrete
  Casbin library. Callers inject an `enforce` function that represents the
  Casbin enforcer and returns a boolean decision.
  """

  alias Arbiter.Policy.Authorizer.Core

  @behaviour Arbiter.Policy.Authorizer

  @impl Arbiter.Policy.Authorizer
  def authorize(target, request) when is_map(target) and is_map(request) do
    with {:ok, policy_version} <- fetch_target_string(target, "policy_version"),
         {:ok, enforce} <- fetch_enforce(target),
         {:ok, request_scope} <- Core.request_scope(request),
         {:ok, roles} <- fetch_roles(target),
         {:ok, true} <- enforce(enforce, request_scope) do
      {:ok, Core.allow(policy_version, request_scope, roles)}
    else
      {:ok, false} -> {:ok, Core.deny(["rbac_denied"], policy_version(target))}
      {:error, reason} -> {:error, reason}
    end
  end

  def authorize(_target, _request), do: {:error, :invalid_authorization_input}

  defp fetch_target_string(target, key) do
    case Core.fetch(target, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _missing_or_invalid -> {:error, :"invalid_#{key}"}
    end
  end

  defp fetch_enforce(target) do
    case Map.get(target, :enforce, Map.get(target, "enforce")) do
      enforce when is_function(enforce, 4) -> {:ok, enforce}
      _missing_or_invalid -> {:error, :invalid_casbin_enforcer}
    end
  end

  defp fetch_roles(target) do
    roles = Map.get(target, :roles, Map.get(target, "roles", []))

    if is_list(roles) and Enum.all?(roles, &Core.valid_string?/1) do
      {:ok, roles}
    else
      {:error, :invalid_roles}
    end
  end

  defp enforce(enforce, request_scope) do
    try do
      case enforce.(
             request_scope.tenant_id,
             request_scope.user_id,
             request_scope.action,
             request_scope.resource_type
           ) do
        decision when is_boolean(decision) -> {:ok, decision}
        _invalid_decision -> {:error, :invalid_casbin_decision}
      end
    rescue
      _error -> {:error, :casbin_enforcer_failed}
    catch
      _kind, _reason -> {:error, :casbin_enforcer_failed}
    end
  end

  defp policy_version(target) do
    case Core.fetch(target, "policy_version") do
      value when is_binary(value) and value != "" -> value
      _missing_or_invalid -> "unknown"
    end
  end
end
