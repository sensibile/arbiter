defmodule ArbiterWeb.Router do
  use ArbiterWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", ArbiterWeb do
    get "/healthz", HealthController, :liveness
    get "/readyz", HealthController, :readiness
  end

  scope "/api", ArbiterWeb do
    pipe_through :api
  end
end
