defmodule Arbiter.Repo.Migrations.CreateDomainSkeleton do
  use Ecto.Migration

  @primary_key_type :binary_id

  def change do
    execute "CREATE EXTENSION IF NOT EXISTS citext", "DROP EXTENSION IF EXISTS citext"

    create table(:tenants, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :isolation_level, :string, null: false, default: "tenant"
      add :policy_version, :string, null: false, default: "policy_v1"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:tenants, [:name])

    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :tenant_id, references(:tenants, type: @primary_key_type, on_delete: :delete_all),
        null: false

      add :email, :citext, null: false
      add :status, :string, null: false, default: "active"
      add :role, :string, null: false
      add :department_ids, {:array, :string}, null: false, default: []
      add :clearance_level, :integer, null: false, default: 0
      add :policy_version, :string, null: false, default: "policy_v1"

      timestamps(type: :utc_datetime)
    end

    create index(:users, [:tenant_id])
    create unique_index(:users, [:tenant_id, :email])

    create table(:groups, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :tenant_id, references(:tenants, type: @primary_key_type, on_delete: :delete_all),
        null: false

      add :name, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:groups, [:tenant_id])
    create unique_index(:groups, [:tenant_id, :name])

    create table(:memberships, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :user_id, references(:users, type: @primary_key_type, on_delete: :delete_all),
        null: false

      add :group_id, references(:groups, type: @primary_key_type, on_delete: :delete_all),
        null: false

      add :tenant_id, references(:tenants, type: @primary_key_type, on_delete: :delete_all),
        null: false

      add :source, :string, null: false
      add :effective_from, :utc_datetime
      add :effective_until, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:memberships, [:tenant_id])
    create index(:memberships, [:user_id])
    create unique_index(:memberships, [:tenant_id, :user_id, :group_id])

    create table(:documents, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :tenant_id, references(:tenants, type: @primary_key_type, on_delete: :delete_all),
        null: false

      add :source, :string, null: false
      add :owner_id, references(:users, type: @primary_key_type, on_delete: :nilify_all)
      add :department_id, :string
      add :classification, :string, null: false, default: "internal"
      add :sensitivity_level, :integer, null: false, default: 0
      add :status, :string, null: false, default: "active"
      add :acl_version, :string, null: false, default: "acl_v1"

      timestamps(type: :utc_datetime)
    end

    create index(:documents, [:tenant_id])
    create index(:documents, [:tenant_id, :source])
    create index(:documents, [:tenant_id, :department_id])

    create table(:chunks, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :document_id, references(:documents, type: @primary_key_type, on_delete: :delete_all),
        null: false

      add :tenant_id, references(:tenants, type: @primary_key_type, on_delete: :delete_all),
        null: false

      add :text, :text, null: false
      add :embedding_id, :string
      add :department_id, :string
      add :sensitivity_level, :integer, null: false, default: 0
      add :visibility, :string, null: false, default: "department"
      add :acl_version, :string, null: false, default: "acl_v1"
      add :policy_version, :string, null: false, default: "policy_v1"

      timestamps(type: :utc_datetime)
    end

    create index(:chunks, [:document_id])
    create index(:chunks, [:tenant_id])
    create index(:chunks, [:tenant_id, :department_id, :sensitivity_level])
    create index(:chunks, [:tenant_id, :visibility])

    create table(:policies, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :tenant_id, references(:tenants, type: @primary_key_type, on_delete: :delete_all),
        null: false

      add :name, :string, null: false
      add :source, :string, null: false
      add :dsl, :text, null: false
      add :ast, :map, null: false, default: %{}
      add :version, :string, null: false
      add :status, :string, null: false, default: "draft"

      timestamps(type: :utc_datetime)
    end

    create index(:policies, [:tenant_id])
    create unique_index(:policies, [:tenant_id, :name, :version])

    create table(:policy_decisions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :tenant_id, references(:tenants, type: @primary_key_type, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: @primary_key_type, on_delete: :nilify_all)
      add :action, :string, null: false
      add :resource_type, :string, null: false
      add :resource_id, :binary_id
      add :decision, :string, null: false
      add :reason, {:array, :string}, null: false, default: []
      add :policy_version, :string, null: false
      add :user_snapshot, :map, null: false, default: %{}
      add :resource_snapshot, :map, null: false, default: %{}

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:policy_decisions, [:tenant_id])
    create index(:policy_decisions, [:tenant_id, :user_id])
    create index(:policy_decisions, [:tenant_id, :resource_type, :resource_id])

    create table(:agent_runs, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :tenant_id, references(:tenants, type: @primary_key_type, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: @primary_key_type, on_delete: :nilify_all)
      add :question, :text, null: false
      add :status, :string, null: false, default: "queued"
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:agent_runs, [:tenant_id])
    create index(:agent_runs, [:tenant_id, :user_id])
    create index(:agent_runs, [:tenant_id, :status])

    create table(:retrieval_traces, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :agent_run_id, references(:agent_runs, type: @primary_key_type, on_delete: :delete_all),
        null: false

      add :tool, :string, null: false
      add :query, :map, null: false, default: %{}
      add :applied_filter, :map, null: false, default: %{}
      add :retrieved_chunk_ids, {:array, :binary_id}, null: false, default: []
      add :accepted_chunk_ids, {:array, :binary_id}, null: false, default: []
      add :rejected_chunk_ids, {:array, :binary_id}, null: false, default: []
      add :policy_version, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:retrieval_traces, [:agent_run_id])
    create index(:retrieval_traces, [:policy_version])
  end
end
