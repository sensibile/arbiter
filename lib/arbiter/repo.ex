defmodule Arbiter.Repo do
  use Boundary, exports: []

  use Ecto.Repo,
    otp_app: :arbiter,
    adapter: Ecto.Adapters.Postgres
end
