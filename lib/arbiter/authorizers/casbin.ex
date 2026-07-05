defmodule Arbiter.Authorizers.Casbin do
  @moduledoc """
  Casbin-backed authorizer shell.

  This module keeps Arbiter's authorizer contract independent from a concrete
  Casbin library. Callers inject an `enforce` function that represents the
  Casbin enforcer and returns a boolean decision.
  """

  alias Arbiter.Policy.Authorizer.Core
  alias Arbiter.Policy.DecisionReason

  @behaviour Arbiter.Policy.Authorizer

  @impl Arbiter.Policy.Authorizer
  def authorize(target, request) when is_map(target) and is_map(request) do
    with {:ok, policy_version} <- fetch_target_string(target, "policy_version"),
         {:ok, enforce} <- fetch_enforce(target),
         {:ok, timeout_ms} <- fetch_timeout(target),
         {:ok, request_scope} <- Core.request_scope(request),
         {:ok, roles} <- fetch_roles(target),
         {:ok, request_tuple} <- request_tuple(target, request, request_scope),
         {:ok, true} <- enforce(enforce, request_tuple, timeout_ms) do
      {:ok, Core.allow(policy_version, request_scope, roles)}
    else
      {:ok, false} -> {:ok, Core.deny([DecisionReason.rbac_denied()], policy_version(target))}
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
      enforce when is_function(enforce, 1) -> {:ok, enforce}
      enforce when is_function(enforce, 4) -> {:ok, enforce}
      _missing_or_invalid -> {:error, :invalid_casbin_enforcer}
    end
  end

  defp fetch_timeout(target) do
    case Map.get(target, :timeout_ms, Map.get(target, "timeout_ms", 1_000)) do
      timeout_ms when is_integer(timeout_ms) and timeout_ms >= 0 -> {:ok, timeout_ms}
      _invalid_timeout -> {:error, :invalid_casbin_timeout}
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

  defp request_tuple(target, request, request_scope) do
    with {:ok, resource_id} <- fetch_optional_string(request, "resource_id"),
         {:ok, object} <- object(target, request_scope.resource_type, resource_id) do
      {:ok,
       %{
         tenant_id: request_scope.tenant_id,
         domain: request_scope.tenant_id,
         user_id: request_scope.user_id,
         subject: subject(target, request_scope.user_id),
         action: request_scope.action,
         resource_type: request_scope.resource_type,
         resource_id: resource_id,
         object: object
       }}
    end
  end

  defp fetch_optional_string(request, key) do
    case Core.fetch(request, key) do
      nil -> {:ok, nil}
      value when is_binary(value) and value != "" -> {:ok, value}
      _invalid_value -> {:error, :"invalid_#{key}"}
    end
  end

  defp subject(target, user_id) do
    namespace = Map.get(target, :subject_namespace, Map.get(target, "subject_namespace", "user"))
    "#{namespace}:#{user_id}"
  end

  defp object(target, resource_type, nil) do
    namespace =
      Map.get(target, :object_namespace, Map.get(target, "object_namespace", resource_type))

    if Core.valid_string?(namespace) do
      {:ok, "#{namespace}:*"}
    else
      {:error, :invalid_object_namespace}
    end
  end

  defp object(target, _resource_type, resource_id) do
    namespace = Map.get(target, :object_namespace, Map.get(target, "object_namespace"))

    cond do
      is_nil(namespace) ->
        {:ok, resource_id}

      Core.valid_string?(namespace) ->
        {:ok, "#{namespace}:#{resource_id}"}

      true ->
        {:error, :invalid_object_namespace}
    end
  end

  defp enforce(enforce, request_tuple, timeout_ms) when is_function(enforce, 1) do
    run_enforcer(fn -> enforce.(request_tuple) end, timeout_ms)
  end

  defp enforce(enforce, request_tuple, timeout_ms) when is_function(enforce, 4) do
    run_enforcer(
      fn ->
        enforce.(
          request_tuple.tenant_id,
          request_tuple.user_id,
          request_tuple.action,
          request_tuple.resource_type
        )
      end,
      timeout_ms
    )
  end

  defp run_enforcer(call, timeout_ms) do
    task = Task.async(fn -> safe_enforce(call) end)

    case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      {:exit, _reason} -> {:error, :casbin_enforcer_failed}
      nil -> {:error, :casbin_enforcer_timeout}
    end
  end

  defp safe_enforce(call) do
    try do
      case call.() do
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
