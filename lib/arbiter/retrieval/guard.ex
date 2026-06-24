defmodule Arbiter.Retrieval.Guard do
  @moduledoc """
  Pure retrieval guard for pre-search filter enforcement and post-search validation.

  This module does not call vector stores, databases, or audit persistence.
  """

  alias Arbiter.Policy.Decision
  alias Arbiter.Policy.Attributes
  alias Arbiter.Policy.ScopeCompiler
  alias Arbiter.Retrieval.GuardError
  alias Arbiter.Retrieval.GuardedQuery
  alias Arbiter.Retrieval.GuardResult

  @reserved_query_keys MapSet.new(["filter", :filter, "allowed_chunk_ids", :allowed_chunk_ids])

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
    with {:ok, chunk_id} <- Attributes.fetch_required(chunk, "id"),
         true <- valid_chunk_id?(chunk_id),
         {:ok, tenant_id} <- Attributes.fetch_required(chunk, "tenant_id"),
         {:ok, department_id} <- Attributes.fetch_required(chunk, "department_id"),
         {:ok, sensitivity_level} <- Attributes.fetch_required(chunk, "sensitivity_level"),
         {:ok, deleted_at} <- Attributes.fetch_present(chunk, "deleted_at"),
         {:ok, policy_version} <- Attributes.fetch_required(chunk, "policy_version") do
      tenant_id == applied_filter["tenant_id"] and
        department_id in applied_filter["department_id"]["$in"] and
        is_integer(sensitivity_level) and
        sensitivity_level <= applied_filter["sensitivity_level"]["$lte"] and
        deleted_at == applied_filter["deleted_at"] and
        policy_version == decision.policy_version
    else
      _missing_or_invalid -> false
    end
  end

  defp chunk_ids(chunks) do
    chunks
    |> Enum.map(&Attributes.fetch_optional(&1, "id"))
    |> Enum.reject(&is_nil/1)
  end

  defp valid_chunk_id?(chunk_id), do: is_binary(chunk_id) and chunk_id != ""

  defp error(reason, message), do: %GuardError{reason: reason, message: message}
end
