defmodule Arbiter.DomainFixtures do
  use Boundary,
    deps: [
      Arbiter.Agents,
      Arbiter.Documents,
      Arbiter.Repo,
      Arbiter.Tenants
    ]

  @moduledoc false

  alias Arbiter.Agents.AgentRun
  alias Arbiter.Documents.Chunk
  alias Arbiter.Documents.Document
  alias Arbiter.Repo
  alias Arbiter.Tenants.Tenant
  alias Arbiter.Tenants.User

  def tenant_fixture(prefix \\ "tenant") do
    %Tenant{}
    |> Tenant.changeset(%{name: "#{prefix}-#{System.unique_integer([:positive])}"})
    |> Repo.insert!()
  end

  def user_fixture(tenant, attrs \\ []) do
    attrs =
      Keyword.merge(
        [
          email: "user-#{System.unique_integer([:positive])}@example.com",
          role: "analyst",
          department_ids: ["finance"],
          clearance_level: 2,
          policy_version: "policy_v1"
        ],
        attrs
      )

    %User{tenant_id: tenant.id}
    |> User.changeset(Map.new(attrs))
    |> Repo.insert!()
  end

  def agent_run_fixture(tenant, user, attrs \\ []) do
    attrs = Keyword.merge([question: "What changed?"], attrs)

    %AgentRun{tenant_id: tenant.id, user_id: user.id}
    |> AgentRun.changeset(Map.new(attrs))
    |> Repo.insert!()
  end

  def document_fixture(tenant, attrs \\ []) do
    attrs =
      Keyword.merge(
        [
          source: "gdrive",
          department_id: "finance",
          classification: "internal",
          sensitivity_level: 1,
          status: "active",
          acl_version: "acl_v1"
        ],
        attrs
      )

    %Document{tenant_id: tenant.id}
    |> Document.changeset(Map.new(attrs))
    |> Repo.insert!()
  end

  def chunk_fixture(tenant, document, attrs \\ []) do
    attrs =
      Keyword.merge(
        [
          text: "renewal risk",
          department_id: "finance",
          sensitivity_level: 1,
          visibility: "department",
          acl_version: "acl_v1",
          policy_version: "policy_v1"
        ],
        attrs
      )

    %Chunk{tenant_id: tenant.id, document_id: document.id}
    |> Chunk.changeset(Map.new(attrs))
    |> Repo.insert!()
  end
end
