defmodule Arbiter.Audit do
  use Boundary,
    deps: [Arbiter.Policy, Arbiter.Repo, Arbiter.Retrieval],
    exports: [AnswerLineage]

  @moduledoc """
  Boundary module for audit lineage persistence.

  This module owns Repo transactions for audit records. Policy evaluation,
  retrieval filtering, and lineage event shaping remain outside this boundary.
  """

  alias Arbiter.Audit.AnswerLineage
  alias Arbiter.Policy.PolicyDecision
  alias Arbiter.Repo
  alias Arbiter.Retrieval.RetrievalTrace
  alias Ecto.Multi

  def record_retrieval_decision(event) when is_map(event) do
    Multi.new()
    |> Multi.insert(
      :policy_decision,
      PolicyDecision.changeset(%PolicyDecision{}, policy_decision_attrs(event))
    )
    |> Multi.run(:retrieval_trace, fn repo, _changes ->
      if record_retrieval_trace?(event) do
        %RetrievalTrace{}
        |> RetrievalTrace.changeset(retrieval_trace_attrs(event))
        |> repo.insert()
      else
        {:ok, nil}
      end
    end)
    |> Repo.transaction()
  end

  def record_retrieval_decision(_event), do: {:error, :invalid_event}

  def record_answer_lineage(attrs) when is_map(attrs) do
    %AnswerLineage{}
    |> AnswerLineage.changeset(attrs)
    |> Repo.insert()
  end

  def record_answer_lineage(_attrs), do: {:error, :invalid_lineage}

  defp policy_decision_attrs(event) do
    %{
      tenant_id: fetch(event, :tenant_id),
      user_id: fetch(event, :user_id),
      action: fetch(event, :action),
      resource_type: fetch(event, :resource_type),
      resource_id: fetch(event, :resource_id),
      decision: fetch(event, :decision),
      reason: fetch(event, :reason, []),
      policy_version: fetch(event, :policy_version),
      user_snapshot: fetch(event, :user_snapshot, %{}),
      resource_snapshot: fetch(event, :resource_snapshot, %{})
    }
  end

  defp retrieval_trace_attrs(event) do
    %{
      agent_run_id: fetch(event, :agent_run_id),
      tool: fetch(event, :tool),
      query: fetch(event, :query, %{}),
      applied_filter: fetch(event, :applied_filter, %{}),
      retrieved_chunk_ids: fetch(event, :retrieved_chunk_ids, []),
      accepted_chunk_ids: fetch(event, :accepted_chunk_ids, []),
      rejected_chunk_ids: fetch(event, :rejected_chunk_ids, []),
      policy_version: fetch(event, :policy_version)
    }
  end

  defp record_retrieval_trace?(event) do
    fetch(event, :status) in ["allowed", "failed_closed"] and
      fetch(event, :agent_run_id) not in [nil, ""] and
      (fetch(event, :applied_filter, %{}) != %{} or fetch(event, :retrieved_chunk_ids, []) != [] or
         fetch(event, :accepted_chunk_ids, []) != [] or
         fetch(event, :rejected_chunk_ids, []) != [])
  end

  defp fetch(map, key, default \\ nil) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end
end
