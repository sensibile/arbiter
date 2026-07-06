defmodule ArbiterWeb.HealthControllerInfraTest do
  use ArbiterWeb.ConnCase, async: false

  alias Arbiter.Repo

  setup_all do
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)
    Ecto.Migrator.run(Repo, :up, all: true)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :manual)
    :ok
  end

  test "GET /readyz reports readiness from database checks", %{conn: conn} do
    conn = get(conn, ~p"/readyz")

    assert %{
             "status" => "ready",
             "checks" => %{
               "database" => %{"status" => "ok"},
               "outbox" => %{
                 "status" => "ok",
                 "pending" => pending,
                 "processing" => processing,
                 "failed" => failed
               }
             }
           } = json_response(conn, 200)

    assert is_integer(pending)
    assert is_integer(processing)
    assert is_integer(failed)
  end
end
