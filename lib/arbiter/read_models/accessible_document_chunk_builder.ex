defmodule Arbiter.ReadModels.AccessibleDocumentChunkBuilder do
  @moduledoc """
  Pure builder for `accessible_document_chunks` projection attributes.

  It accepts already-loaded user and chunk data plus a policy decision. It does
  not call Repo, vector stores, clocks, or external adapters.
  """

  alias Arbiter.Policy.Attributes
  alias Arbiter.Policy.Decision
  alias Arbiter.Policy.ScopeCompiler

  def build(user, chunk, %Decision{} = decision, %DateTime{} = projected_at) do
    with {:ok, applied_filter} <- compile_filter(decision),
         {:ok, user_attrs} <- user_attrs(user, decision),
         {:ok, chunk_attrs} <- chunk_attrs(chunk),
         :ok <- require_projection_allowed(user_attrs, chunk_attrs, decision, applied_filter) do
      {:ok,
       %{
         tenant_id: user_attrs.tenant_id,
         user_id: user_attrs.user_id,
         chunk_id: chunk_attrs.chunk_id,
         document_id: chunk_attrs.document_id,
         user_policy_version: user_attrs.policy_version,
         chunk_policy_version: chunk_attrs.policy_version,
         chunk_deleted_at: chunk_attrs.deleted_at,
         access_reason: decision.reason,
         projected_at: projected_at,
         invalidated_at: nil
       }}
    end
  end

  def build(_user, _chunk, _decision, _projected_at), do: {:error, :invalid_projection_input}

  defp compile_filter(%Decision{} = decision) do
    case ScopeCompiler.to_vector_filter(decision) do
      {:ok, applied_filter} -> {:ok, applied_filter}
      {:error, error} -> {:error, error.reason}
    end
  end

  defp user_attrs(user, %Decision{} = decision) do
    with {:ok, user_id} <- fetch_non_empty(user, "id"),
         {:ok, tenant_id} <- fetch_non_empty(user, "tenant_id"),
         {:ok, policy_version} <- fetch_non_empty(user, "policy_version"),
         :ok <- require_equal(policy_version, decision.policy_version, :stale_user_policy_version) do
      {:ok, %{user_id: user_id, tenant_id: tenant_id, policy_version: policy_version}}
    end
  end

  defp chunk_attrs(chunk) do
    with {:ok, chunk_id} <- fetch_non_empty(chunk, "id"),
         {:ok, document_id} <- fetch_non_empty(chunk, "document_id"),
         {:ok, tenant_id} <- fetch_non_empty(chunk, "tenant_id"),
         {:ok, department_id} <- fetch_non_empty(chunk, "department_id"),
         {:ok, sensitivity_level} <- fetch_integer(chunk, "sensitivity_level"),
         {:ok, deleted_at} <- fetch_present(chunk, "deleted_at"),
         {:ok, policy_version} <- fetch_non_empty(chunk, "policy_version") do
      {:ok,
       %{
         chunk_id: chunk_id,
         document_id: document_id,
         tenant_id: tenant_id,
         department_id: department_id,
         sensitivity_level: sensitivity_level,
         deleted_at: deleted_at,
         policy_version: policy_version
       }}
    end
  end

  defp require_projection_allowed(user_attrs, chunk_attrs, decision, applied_filter) do
    cond do
      user_attrs.tenant_id != chunk_attrs.tenant_id ->
        {:error, :tenant_mismatch}

      chunk_attrs.tenant_id != applied_filter["tenant_id"] ->
        {:error, :outside_tenant_scope}

      chunk_attrs.department_id not in applied_filter["department_id"]["$in"] ->
        {:error, :outside_department_scope}

      chunk_attrs.sensitivity_level > applied_filter["sensitivity_level"]["$lte"] ->
        {:error, :outside_sensitivity_scope}

      chunk_attrs.deleted_at != applied_filter["deleted_at"] ->
        {:error, :chunk_deleted}

      chunk_attrs.policy_version != decision.policy_version ->
        {:error, :stale_chunk_policy_version}

      true ->
        :ok
    end
  end

  defp fetch_non_empty(value, key) do
    case Attributes.fetch_required(value, key) do
      {:ok, fetched_value} when is_binary(fetched_value) and fetched_value != "" ->
        {:ok, fetched_value}

      {:ok, _invalid_value} ->
        {:error, :"invalid_#{key}"}

      {:error, _reason} ->
        {:error, :"missing_#{key}"}
    end
  end

  defp fetch_present(value, key) do
    case Attributes.fetch_present(value, key) do
      {:ok, fetched_value} -> {:ok, fetched_value}
      {:error, _reason} -> {:error, :"missing_#{key}"}
    end
  end

  defp fetch_integer(value, key) do
    case Attributes.fetch_required(value, key) do
      {:ok, fetched_value} when is_integer(fetched_value) -> {:ok, fetched_value}
      {:ok, _invalid_value} -> {:error, :"invalid_#{key}"}
      {:error, _reason} -> {:error, :"missing_#{key}"}
    end
  end

  defp require_equal(value, value, _reason), do: :ok
  defp require_equal(_left, _right, reason), do: {:error, reason}
end
