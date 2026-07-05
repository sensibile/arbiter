defmodule Arbiter.Policy.Authorizer.Static do
  @moduledoc """
  Static RBAC/ABAC authorizer for tests and local development.

  The policy data is passed in as a map. Role and permission matching is the
  RBAC gate; user attributes then become the ABAC retrieval scope.
  """

  alias Arbiter.Policy.Authorizer.Core

  @behaviour Arbiter.Policy.Authorizer

  @impl Arbiter.Policy.Authorizer
  def authorize(policy, request) when is_map(policy) and is_map(request) do
    with {:ok, policy_version} <- fetch_policy_string(policy, "policy_version"),
         {:ok, request_scope} <- Core.request_scope(request),
         {:ok, roles} <- roles_for(policy, request_scope.user_id),
         :ok <- permit?(policy, roles, request_scope) do
      {:ok, Core.allow(policy_version, request_scope, roles)}
    else
      {:deny, reason, policy_version} -> {:ok, Core.deny(reason, policy_version)}
      {:error, reason} -> {:error, reason}
    end
  end

  def authorize(_policy, _request), do: {:error, :invalid_authorization_input}

  defp roles_for(policy, user_id) do
    role_assignments =
      Map.get(policy, :role_assignments, Map.get(policy, "role_assignments", %{}))

    with true <- is_map(role_assignments),
         roles <- Map.get(role_assignments, user_id, []),
         true <- is_list(roles),
         true <- Enum.all?(roles, &Core.valid_string?/1) do
      {:ok, roles}
    else
      _invalid_role_assignment -> {:error, :invalid_role_assignment}
    end
  end

  defp permit?(policy, roles, request_scope) do
    policy_version =
      Map.get(policy, :policy_version, Map.get(policy, "policy_version", "unknown"))

    permissions = Map.get(policy, :permissions, Map.get(policy, "permissions", []))

    cond do
      not is_list(permissions) ->
        {:error, :invalid_permissions}

      not Enum.all?(permissions, &valid_permission?/1) ->
        {:error, :invalid_permission}

      Enum.any?(permissions, &permission_matches?(&1, roles, request_scope)) ->
        :ok

      true ->
        {:deny, ["rbac_denied"], policy_version}
    end
  end

  defp valid_permission?(permission) when is_map(permission) do
    Core.valid_string?(Core.fetch(permission, "role")) and
      Core.valid_string?(Core.fetch(permission, "action")) and
      Core.valid_string?(Core.fetch(permission, "resource_type")) and
      Core.valid_optional_string?(Core.fetch(permission, "tenant_id"))
  end

  defp valid_permission?(_permission), do: false

  defp permission_matches?(permission, roles, request_scope) when is_map(permission) do
    role = Core.fetch(permission, "role")
    action = Core.fetch(permission, "action")
    resource_type = Core.fetch(permission, "resource_type")
    tenant_id = Core.fetch(permission, "tenant_id")

    role in roles and
      action == request_scope.action and
      resource_type == request_scope.resource_type and
      (is_nil(tenant_id) or tenant_id == request_scope.tenant_id)
  end

  defp permission_matches?(_permission, _roles, _request_scope), do: false

  defp fetch_policy_string(policy, key) do
    case Core.fetch(policy, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _missing_or_invalid -> {:error, :"invalid_#{key}"}
    end
  end
end
