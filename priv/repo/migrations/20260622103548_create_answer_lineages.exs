defmodule Arbiter.Repo.Migrations.CreateAnswerLineages do
  use Ecto.Migration

  @primary_key_type :binary_id

  def change do
    create table(:answer_lineages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :answer_id, :binary_id, null: false

      add :agent_run_id, references(:agent_runs, type: @primary_key_type, on_delete: :delete_all),
        null: false

      add :tenant_id, references(:tenants, type: @primary_key_type, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: @primary_key_type, on_delete: :nilify_all)
      add :used_chunks, {:array, :map}, null: false, default: []
      add :policy_decision_ids, {:array, :binary_id}, null: false, default: []

      timestamps(type: :utc_datetime)
    end

    create index(:answer_lineages, [:agent_run_id])
    create index(:answer_lineages, [:tenant_id])
    create index(:answer_lineages, [:tenant_id, :user_id])
    create unique_index(:answer_lineages, [:tenant_id, :answer_id])
  end
end
