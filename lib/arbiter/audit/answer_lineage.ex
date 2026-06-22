defmodule Arbiter.Audit.AnswerLineage do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "answer_lineages" do
    field :answer_id, :binary_id
    field :used_chunks, {:array, :map}, default: []
    field :policy_decision_ids, {:array, :binary_id}, default: []

    belongs_to :agent_run, Arbiter.Agents.AgentRun
    belongs_to :tenant, Arbiter.Tenants.Tenant
    belongs_to :user, Arbiter.Tenants.User

    timestamps(type: :utc_datetime)
  end

  def changeset(answer_lineage, attrs) do
    answer_lineage
    |> cast(attrs, [
      :answer_id,
      :agent_run_id,
      :tenant_id,
      :user_id,
      :used_chunks,
      :policy_decision_ids
    ])
    |> validate_required([
      :answer_id,
      :agent_run_id,
      :tenant_id,
      :used_chunks,
      :policy_decision_ids
    ])
    |> validate_non_empty_list(:used_chunks)
    |> validate_non_empty_list(:policy_decision_ids)
    |> validate_used_chunks()
    |> unique_constraint(:answer_id, name: :answer_lineages_tenant_id_answer_id_index)
  end

  defp validate_non_empty_list(changeset, field) do
    value = get_field(changeset, field)

    if is_list(value) and value != [] do
      changeset
    else
      add_error(changeset, field, "should have at least 1 item(s)")
    end
  end

  defp validate_used_chunks(changeset) do
    validate_change(changeset, :used_chunks, fn :used_chunks, used_chunks ->
      if Enum.all?(used_chunks, &valid_used_chunk?/1) do
        []
      else
        [used_chunks: "must include chunk_id, document_id, and policy_version for every chunk"]
      end
    end)
  end

  defp valid_used_chunk?(%{
         "chunk_id" => chunk_id,
         "document_id" => document_id,
         "policy_version" => policy_version
       }) do
    valid_uuid?(chunk_id) and valid_uuid?(document_id) and is_binary(policy_version) and
      policy_version != ""
  end

  defp valid_used_chunk?(_chunk), do: false

  defp valid_uuid?(value) when is_binary(value), do: match?({:ok, _uuid}, Ecto.UUID.cast(value))
  defp valid_uuid?(_value), do: false
end
