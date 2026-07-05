defmodule Arbiter.Policy.AuthorizationRequest do
  @moduledoc """
  Normalized request shape accepted by Arbiter authorizers.

  Gateway tool calls and plain maps are normalized into this struct before RBAC
  and ABAC decisions are made. The struct keeps authorizer inputs explicit
  without giving policy core ownership of Gateway, Repo, clocks, or adapters.
  """

  @enforce_keys [:tenant_id, :user_id, :action, :resource_type, :user_snapshot]
  defstruct [
    :tenant_id,
    :user_id,
    :agent_run_id,
    :tool,
    :action,
    :resource_type,
    :resource_id,
    :query,
    :user_snapshot,
    :resource_snapshot
  ]

  @type t :: %__MODULE__{
          tenant_id: String.t(),
          user_id: String.t(),
          agent_run_id: String.t() | nil,
          tool: String.t() | nil,
          action: String.t(),
          resource_type: String.t(),
          resource_id: String.t() | nil,
          query: map() | nil,
          user_snapshot: map(),
          resource_snapshot: map() | nil
        }

  @required_string_fields [:tenant_id, :user_id, :action, :resource_type]
  @optional_string_fields [:agent_run_id, :tool, :resource_id]

  def normalize(%__MODULE__{} = request), do: {:ok, request}

  def normalize(request) when is_map(request) do
    with {:ok, attrs} <- fetch_required_strings(request),
         {:ok, attrs} <- fetch_optional_strings(request, attrs),
         {:ok, user_snapshot} <- fetch_user_snapshot(request),
         {:ok, resource_snapshot} <- fetch_optional_map(request, :resource_snapshot),
         {:ok, query} <- fetch_optional_map(request, :query) do
      {:ok,
       struct!(
         __MODULE__,
         attrs
         |> Map.put(:user_snapshot, user_snapshot)
         |> Map.put(:resource_snapshot, resource_snapshot)
         |> Map.put(:query, query)
       )}
    end
  end

  def normalize(_request), do: {:error, :invalid_authorization_request}

  defp fetch_required_strings(request) do
    Enum.reduce_while(@required_string_fields, {:ok, %{}}, fn field, {:ok, attrs} ->
      case fetch(request, field) do
        value when is_binary(value) and value != "" ->
          {:cont, {:ok, Map.put(attrs, field, value)}}

        _missing_or_invalid ->
          {:halt, {:error, :"invalid_#{field}"}}
      end
    end)
  end

  defp fetch_optional_strings(request, attrs) do
    Enum.reduce_while(@optional_string_fields, {:ok, attrs}, fn field, {:ok, attrs} ->
      case fetch(request, field) do
        nil ->
          {:cont, {:ok, Map.put(attrs, field, nil)}}

        value when is_binary(value) and value != "" ->
          {:cont, {:ok, Map.put(attrs, field, value)}}

        _invalid_value ->
          {:halt, {:error, :"invalid_#{field}"}}
      end
    end)
  end

  defp fetch_user_snapshot(request) do
    case fetch(request, :user_snapshot) do
      snapshot when is_map(snapshot) -> {:ok, snapshot}
      _missing_or_invalid -> {:error, :invalid_user_snapshot}
    end
  end

  defp fetch_optional_map(request, field) do
    case fetch(request, field) do
      nil -> {:ok, nil}
      value when is_map(value) -> {:ok, value}
      _invalid_value -> {:error, :"invalid_#{field}"}
    end
  end

  defp fetch(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
