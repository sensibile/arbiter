defmodule Arbiter.Policy.Authorizer.Static do
  @moduledoc """
  Static RBAC/ABAC authorizer for tests and local development.

  The policy data is passed in as a map. Role and permission matching is the
  RBAC gate; user attributes then become the ABAC retrieval scope.
  """

  alias Arbiter.Policy.Attributes
  alias Arbiter.Policy.Decision

  @behaviour Arbiter.Policy.Authorizer

  @impl Arbiter.Policy.Authorizer
  def authorize(policy, request) when is_map(policy) and is_map(request) do
    with {:ok, policy_version} <- fetch_policy_string(policy, "policy_version"),
         {:ok, request_scope} <- request_scope(request),
         :ok <- validate_user_tenant(request_scope),
         {:ok, roles} <- roles_for(policy, request_scope.user_id),
         :ok <- permit?(policy, roles, request_scope) do
      {:ok, allow(policy_version, request_scope, roles)}
    else
      {:deny, reason, policy_version} -> {:ok, deny(reason, policy_version)}
      {:error, reason} -> {:error, reason}
    end
  end

  def authorize(_policy, _request), do: {:error, :invalid_authorization_input}

  defp request_scope(request) do
    with {:ok, tenant_id} <- fetch_request_string(request, :tenant_id),
         {:ok, user_id} <- fetch_request_string(request, :user_id),
         {:ok, action} <- fetch_request_string(request, :action),
         {:ok, resource_type} <- fetch_request_string(request, :resource_type),
         {:ok, user_snapshot} <- fetch_user_snapshot(request),
         {:ok, user_tenant_id} <- fetch_snapshot_string(user_snapshot, "tenant_id"),
         {:ok, departments} <- fetch_departments(user_snapshot),
         {:ok, clearance_level} <- fetch_clearance_level(user_snapshot) do
      {:ok,
       %{
         tenant_id: tenant_id,
         user_id: user_id,
         action: action,
         resource_type: resource_type,
         user_tenant_id: user_tenant_id,
         departments: departments,
         clearance_level: clearance_level
       }}
    end
  end

  defp validate_user_tenant(%{tenant_id: tenant_id, user_tenant_id: tenant_id}), do: :ok
  defp validate_user_tenant(_scope), do: {:error, :tenant_scope_mismatch}

  defp roles_for(policy, user_id) do
    role_assignments =
      Map.get(policy, :role_assignments, Map.get(policy, "role_assignments", %{}))

    roles = Map.get(role_assignments, user_id, [])

    if is_list(roles) and Enum.all?(roles, &valid_string?/1) do
      {:ok, roles}
    else
      {:error, :invalid_role_assignment}
    end
  end

  defp permit?(policy, roles, request_scope) do
    policy_version =
      Map.get(policy, :policy_version, Map.get(policy, "policy_version", "unknown"))

    permissions = Map.get(policy, :permissions, Map.get(policy, "permissions", []))

    cond do
      not is_list(permissions) ->
        {:error, :invalid_permissions}

      Enum.any?(permissions, &permission_matches?(&1, roles, request_scope)) ->
        :ok

      true ->
        {:deny, ["rbac_denied"], policy_version}
    end
  end

  defp permission_matches?(permission, roles, request_scope) when is_map(permission) do
    role = fetch(permission, "role")
    action = fetch(permission, "action")
    resource_type = fetch(permission, "resource_type")
    tenant_id = fetch(permission, "tenant_id")

    role in roles and
      action == request_scope.action and
      resource_type == request_scope.resource_type and
      (is_nil(tenant_id) or tenant_id == request_scope.tenant_id)
  end

  defp permission_matches?(_permission, _roles, _request_scope), do: false

  defp allow(policy_version, request_scope, roles) do
    %Decision{
      decision: :allow,
      reason: ["rbac_allowed", "tenant_scope_matched", "abac_scope_built"],
      policy_version: policy_version,
      scope: %{
        "tenant_id" => request_scope.tenant_id,
        "departments" => request_scope.departments,
        "max_sensitivity" => request_scope.clearance_level,
        "roles" => roles
      }
    }
  end

  defp deny(reason, policy_version) do
    %Decision{decision: :deny, reason: reason, policy_version: policy_version, scope: %{}}
  end

  defp fetch_policy_string(policy, key) do
    case fetch(policy, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _missing_or_invalid -> {:error, :"invalid_#{key}"}
    end
  end

  defp fetch_request_string(request, key) do
    case Map.get(request, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _missing_or_invalid -> {:error, :"invalid_#{key}"}
    end
  end

  defp fetch_user_snapshot(request) do
    case Map.get(request, :user_snapshot) do
      snapshot when is_map(snapshot) -> {:ok, snapshot}
      _missing_or_invalid -> {:error, :invalid_user_snapshot}
    end
  end

  defp fetch_snapshot_string(snapshot, key) do
    case Attributes.fetch_required(snapshot, key) do
      {:ok, value} when is_binary(value) and value != "" -> {:ok, value}
      {:ok, _invalid_value} -> {:error, :"invalid_user_#{key}"}
      {:error, _reason} -> {:error, :"missing_user_#{key}"}
    end
  end

  defp fetch_departments(snapshot) do
    case Attributes.fetch_required(snapshot, "department_ids") do
      {:ok, departments} when is_list(departments) ->
        if Enum.all?(departments, &valid_string?/1) do
          {:ok, departments}
        else
          {:error, :invalid_user_department_ids}
        end

      {:ok, _invalid_value} ->
        {:error, :invalid_user_department_ids}

      {:error, _reason} ->
        {:error, :missing_user_department_ids}
    end
  end

  defp fetch_clearance_level(snapshot) do
    case Attributes.fetch_required(snapshot, "clearance_level") do
      {:ok, clearance_level} when is_integer(clearance_level) and clearance_level >= 0 ->
        {:ok, clearance_level}

      {:ok, _invalid_value} ->
        {:error, :invalid_user_clearance_level}

      {:error, _reason} ->
        {:error, :missing_user_clearance_level}
    end
  end

  defp fetch(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key, Map.get(map, atom_key(key)))
  end

  defp atom_key("policy_version"), do: :policy_version
  defp atom_key("role_assignments"), do: :role_assignments
  defp atom_key("permissions"), do: :permissions
  defp atom_key("role"), do: :role
  defp atom_key("action"), do: :action
  defp atom_key("resource_type"), do: :resource_type
  defp atom_key("tenant_id"), do: :tenant_id
  defp atom_key(_key), do: nil

  defp valid_string?(value), do: is_binary(value) and value != ""
end
