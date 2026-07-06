defmodule Arbiter.Operations.HealthTest do
  use ExUnit.Case, async: true

  alias Arbiter.Operations.Health

  defmodule ReadyRepo do
    def query("SELECT 1", [], _opts), do: {:ok, %{rows: [[1]]}}
    def all(_query, _opts), do: [{"pending", 2}, {"failed", 1}]
  end

  defmodule UnavailableRepo do
    def query("SELECT 1", [], _opts), do: {:error, :database_down}
  end

  test "liveness is process-local and reports ok" do
    assert Health.liveness() == %{
             status: "ok",
             checks: %{
               application: %{status: "ok"}
             }
           }
  end

  test "readiness reports database and bounded outbox counts" do
    readiness = Health.readiness(repo: ReadyRepo)

    assert readiness == %{
             status: "ready",
             checks: %{
               database: %{status: "ok"},
               outbox: %{status: "ok", pending: 2, processing: 0, failed: 1}
             }
           }

    assert Health.ready?(readiness)
  end

  test "readiness fails closed when database cannot be checked" do
    readiness = Health.readiness(repo: UnavailableRepo)

    assert readiness == %{
             status: "not_ready",
             checks: %{
               database: %{status: "error", reason: "database_unavailable"},
               outbox: %{status: "unknown"}
             }
           }

    refute Health.ready?(readiness)
  end

  test "readiness rejects invalid repo dependencies" do
    assert Health.readiness(repo: :not_a_loaded_repo) == %{
             status: "not_ready",
             checks: %{
               database: %{status: "error", reason: "database_unavailable"},
               outbox: %{status: "unknown"}
             }
           }

    refute Health.ready?(%{status: "not_ready"})
  end
end
