defmodule Arbiter.Authorizers.RepoBacked do
  @moduledoc """
  Repo-backed authorizer shell.

  It loads the current user row as the authoritative role and ABAC attribute
  source, then delegates RBAC permission matching and scope shaping to the pure
  static authorizer contract.
  """

  import Ecto.Query

  alias Arbiter.Policy.Authorizer.Core
  alias Arbiter.Policy.Authorizer.Static
  alias Arbiter.Repo
  alias Arbiter.Tenants.User

  @behaviour Arbiter.Policy.Authorizer

  @impl Arbiter.Policy.Authorizer
  def authorize(target, request) when is_map(target) and is_map(request) do
    with {:ok, permissions} <- fetch_permissions(target),
         {:ok, request_scope} <- Core.request_scope(request),
         {:ok, user} <- load_user(repo(target), request_scope),
         :ok <- validate_loaded_user_snapshot(request_scope, user),
         {:ok, decision} <- authorize_loaded_user(permissions, request, user) do
      {:ok, decision}
    end
  end

  def authorize(_target, _request), do: {:error, :invalid_authorization_input}

  defp repo(target), do: Map.get(target, :repo, Map.get(target, "repo", Repo))

  defp fetch_permissions(target) do
    case Map.get(target, :permissions, Map.get(target, "permissions")) do
      permissions when is_list(permissions) -> {:ok, permissions}
      _missing_or_invalid -> {:error, :invalid_permissions}
    end
  end

  defp load_user(repo, %{tenant_id: tenant_id, user_id: user_id}) when is_atom(repo) do
    query =
      from user in User,
        where: user.tenant_id == ^tenant_id and user.id == ^user_id

    case repo.one(query) do
      %User{} = user -> {:ok, user}
      nil -> {:error, :user_not_found}
    end
  end

  defp load_user(_repo, _request_scope), do: {:error, :invalid_repo}

  defp validate_loaded_user_snapshot(request_scope, %User{} = user) do
    with :ok <-
           require_snapshot_value(
             request_scope.user_snapshot,
             "policy_version",
             user.policy_version
           ),
         :ok <-
           require_equal(request_scope.departments, user.department_ids, :stale_user_departments),
         :ok <-
           require_equal(
             request_scope.clearance_level,
             user.clearance_level,
             :stale_user_clearance
           ) do
      :ok
    end
  end

  defp require_snapshot_value(snapshot, key, expected_value) do
    case Core.fetch(snapshot, key) do
      ^expected_value -> :ok
      value when is_nil(value) or value == "" -> {:error, :"missing_user_#{key}"}
      _stale_value -> {:error, :"stale_user_#{key}"}
    end
  end

  defp require_equal(value, value, _reason), do: :ok
  defp require_equal(_value, _expected_value, reason), do: {:error, reason}

  defp authorize_loaded_user(_permissions, _request, %User{status: status} = user)
       when status != "active" do
    {:ok, Core.deny(["inactive_user"], user.policy_version)}
  end

  defp authorize_loaded_user(permissions, request, %User{} = user) do
    Static.authorize(
      %{
        policy_version: user.policy_version,
        role_assignments: %{user.id => [user.role]},
        permissions: permissions
      },
      request
    )
  end
end
