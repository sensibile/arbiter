defmodule Arbiter.Retrieval.RetrievalTrace do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "retrieval_traces" do
    field :tool, :string
    field :query, :map, default: %{}
    field :applied_filter, :map, default: %{}
    field :retrieved_chunk_ids, {:array, :binary_id}, default: []
    field :accepted_chunk_ids, {:array, :binary_id}, default: []
    field :rejected_chunk_ids, {:array, :binary_id}, default: []
    field :policy_version, :string

    belongs_to :agent_run, Arbiter.Agents.AgentRun

    timestamps(type: :utc_datetime)
  end

  def changeset(retrieval_trace, attrs) do
    retrieval_trace
    |> cast(attrs, [
      :tool,
      :query,
      :applied_filter,
      :retrieved_chunk_ids,
      :accepted_chunk_ids,
      :rejected_chunk_ids,
      :policy_version
    ])
    |> validate_required([
      :tool,
      :query,
      :applied_filter,
      :retrieved_chunk_ids,
      :accepted_chunk_ids,
      :rejected_chunk_ids,
      :policy_version
    ])
  end
end
