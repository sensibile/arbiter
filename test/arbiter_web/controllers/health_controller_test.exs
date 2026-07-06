defmodule ArbiterWeb.HealthControllerTest do
  use ArbiterWeb.ConnCase, async: true

  test "GET /healthz reports process liveness without requiring database access", %{conn: conn} do
    conn = get(conn, ~p"/healthz")

    assert json_response(conn, 200) == %{
             "status" => "ok",
             "checks" => %{
               "application" => %{"status" => "ok"}
             }
           }
  end
end
