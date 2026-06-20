defmodule Arbiter.Agents.AgentRun do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "agent_runs" do
    field :question, :string
    field :status, :string, default: "queued"
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime

    belongs_to :tenant, Arbiter.Tenants.Tenant
    belongs_to :user, Arbiter.Tenants.User
    has_many :retrieval_traces, Arbiter.Retrieval.RetrievalTrace

    timestamps(type: :utc_datetime)
  end

  def changeset(agent_run, attrs) do
    agent_run
    |> cast(attrs, [:question, :status, :started_at, :completed_at])
    |> validate_required([:question, :status])
  end
end
