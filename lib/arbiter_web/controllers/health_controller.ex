defmodule ArbiterWeb.HealthController do
  use ArbiterWeb, :controller

  def liveness(conn, _params) do
    json(conn, Arbiter.health_liveness())
  end

  def readiness(conn, _params) do
    readiness = Arbiter.health_readiness()

    conn
    |> put_status(readiness_status(readiness))
    |> json(readiness)
  end

  defp readiness_status(readiness) do
    if Arbiter.health_ready?(readiness), do: :ok, else: :service_unavailable
  end
end
