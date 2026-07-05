defmodule Arbiter.Tenants do
  @moduledoc false

  use Boundary,
    deps: [],
    exports: [Tenant, User, Group, Membership]
end
