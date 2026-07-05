defmodule Arbiter.Authorizers do
  @moduledoc false

  use Boundary,
    deps: [
      Arbiter.Policy,
      Arbiter.Repo,
      Arbiter.Tenants
    ],
    exports: [Casbin, RepoBacked]
end
