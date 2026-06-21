defmodule Arbiter.Retrieval.Guard do
  @moduledoc """
  Pure retrieval guard for pre-search filter enforcement and post-search validation.

  This module does not call vector stores, databases, or audit persistence.
  """

  alias Arbiter.Policy.Decision
  alias Arbiter.Policy.ScopeCompiler
  alias Arbiter.Retrieval.GuardError
  alias Arbiter.Retrieval.GuardedQuery
  alias Arbiter.Retrieval.GuardResult

  @reserved_query_keys MapSet.new(["filter", :filter])

  def guard_vector_query(query, %Decision{} = decision) when is_map(query) do
    with {:ok, applied_filter} <- ScopeCompiler.to_vector_filter(decision) do
      {:ok,
       %GuardedQuery{
         query: strip_caller_filters(query),
         applied_filter: applied_filter,
         policy_version: decision.policy_version
       }}
    end
  end

  def guard_vector_query(_query, _decision),
    do: {:error, error(:invalid_query, "query must be a map")}

  def post_validate(chunks, %Decision{} = decision) when is_list(chunks) do
    with {:ok, applied_filter} <- ScopeCompiler.to_vector_filter(decision) do
      {accepted_chunks, rejected_chunks} =
        Enum.split_with(chunks, &chunk_allowed?(&1, decision, applied_filter))

      {:ok,
       %GuardResult{
         retrieved_chunks: chunks,
         accepted_chunks: accepted_chunks,
         rejected_chunks: rejected_chunks,
         retrieved_chunk_ids: chunk_ids(chunks),
         accepted_chunk_ids: chunk_ids(accepted_chunks),
         rejected_chunk_ids: chunk_ids(rejected_chunks),
         applied_filter: applied_filter,
         policy_version: decision.policy_version
       }}
    end
  end

  def post_validate(_chunks, _decision),
    do: {:error, error(:invalid_chunks, "chunks must be a list")}

  defp strip_caller_filters(query) do
    Map.reject(query, fn {key, _value} -> MapSet.member?(@reserved_query_keys, key) end)
  end

  defp chunk_allowed?(chunk, decision, applied_filter) do
    with {:ok, chunk_id} <- fetch_required(chunk, "id"),
         true <- valid_chunk_id?(chunk_id),
         {:ok, tenant_id} <- fetch_required(chunk, "tenant_id"),
         {:ok, department_id} <- fetch_required(chunk, "department_id"),
         {:ok, sensitivity_level} <- fetch_required(chunk, "sensitivity_level"),
         {:ok, deleted} <- fetch_required(chunk, "deleted"),
         {:ok, policy_version} <- fetch_required(chunk, "policy_version") do
      tenant_id == applied_filter["tenant_id"] and
        department_id in applied_filter["department_id"]["$in"] and
        is_integer(sensitivity_level) and
        sensitivity_level <= applied_filter["sensitivity_level"]["$lte"] and
        deleted == applied_filter["deleted"] and
        policy_version == decision.policy_version
    else
      _missing_or_invalid -> false
    end
  end

  defp chunk_ids(chunks) do
    chunks
    |> Enum.map(&fetch_optional(&1, "id"))
    |> Enum.reject(&is_nil/1)
  end

  defp fetch_required(value, key) do
    case fetch_optional(value, key) do
      nil -> {:error, :missing_metadata}
      fetched_value -> {:ok, fetched_value}
    end
  end

  defp fetch_optional(value, key) when is_map(value) do
    cond do
      Map.has_key?(value, key) -> Map.get(value, key)
      Map.has_key?(value, known_atom_key(key)) -> Map.get(value, known_atom_key(key))
      true -> nil
    end
  end

  defp fetch_optional(_value, _key), do: nil

  defp known_atom_key("id"), do: :id
  defp known_atom_key("tenant_id"), do: :tenant_id
  defp known_atom_key("department_id"), do: :department_id
  defp known_atom_key("sensitivity_level"), do: :sensitivity_level
  defp known_atom_key("deleted"), do: :deleted
  defp known_atom_key("policy_version"), do: :policy_version

  defp valid_chunk_id?(chunk_id), do: is_binary(chunk_id) and chunk_id != ""

  defp error(reason, message), do: %GuardError{reason: reason, message: message}
end
