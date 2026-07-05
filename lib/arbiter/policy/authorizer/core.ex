defmodule Arbiter.Policy.Authorizer.Core do
  @moduledoc """
  Shared pure helpers for authorizer implementations.

  This module validates request identity and ABAC scope data without owning Repo,
  external policy engines, clocks, IDs, or audit persistence.
  """

  alias Arbiter.Policy.Attributes
  alias Arbiter.Policy.Decision

  def request_scope(request) when is_map(request) do
    with {:ok, tenant_id} <- fetch_request_string(request, :tenant_id),
         {:ok, user_id} <- fetch_request_string(request, :user_id),
         {:ok, action} <- fetch_request_string(request, :action),
         {:ok, resource_type} <- fetch_request_string(request, :resource_type),
         {:ok, user_snapshot} <- fetch_user_snapshot(request),
         {:ok, snapshot_user_id} <- fetch_snapshot_string(user_snapshot, "id"),
         {:ok, user_tenant_id} <- fetch_snapshot_string(user_snapshot, "tenant_id"),
         :ok <- validate_user_identity(user_id, snapshot_user_id),
         :ok <- validate_user_tenant(tenant_id, user_tenant_id),
         {:ok, departments} <- fetch_departments(user_snapshot),
         {:ok, clearance_level} <- fetch_clearance_level(user_snapshot) do
      {:ok,
       %{
         tenant_id: tenant_id,
         user_id: user_id,
         snapshot_user_id: snapshot_user_id,
         action: action,
         resource_type: resource_type,
         user_tenant_id: user_tenant_id,
         departments: departments,
         clearance_level: clearance_level,
         user_snapshot: user_snapshot
       }}
    end
  end

  def request_scope(_request), do: {:error, :invalid_authorization_request}

  def allow(policy_version, request_scope, roles) do
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

  def deny(reason, policy_version) do
    %Decision{decision: :deny, reason: reason, policy_version: policy_version, scope: %{}}
  end

  def fetch(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key, Map.get(map, atom_key(key)))
  end

  def valid_string?(value), do: is_binary(value) and value != ""
  def valid_optional_string?(nil), do: true
  def valid_optional_string?(value), do: valid_string?(value)

  defp validate_user_identity(user_id, user_id), do: :ok

  defp validate_user_identity(_request_user_id, _snapshot_user_id),
    do: {:error, :user_id_mismatch}

  defp validate_user_tenant(tenant_id, tenant_id), do: :ok

  defp validate_user_tenant(_request_tenant_id, _user_tenant_id),
    do: {:error, :tenant_scope_mismatch}

  defp fetch_request_string(request, key) do
    case Map.get(request, key, Map.get(request, Atom.to_string(key))) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _missing_or_invalid -> {:error, :"invalid_#{key}"}
    end
  end

  defp fetch_user_snapshot(request) do
    case Map.get(request, :user_snapshot, Map.get(request, "user_snapshot")) do
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

  defp atom_key("policy_version"), do: :policy_version
  defp atom_key("role_assignments"), do: :role_assignments
  defp atom_key("permissions"), do: :permissions
  defp atom_key("role"), do: :role
  defp atom_key("action"), do: :action
  defp atom_key("resource_type"), do: :resource_type
  defp atom_key("tenant_id"), do: :tenant_id
  defp atom_key(_key), do: nil
end
