defmodule Arbiter.Repo do
  use Ecto.Repo,
    otp_app: :arbiter,
    adapter: Ecto.Adapters.Postgres
end
