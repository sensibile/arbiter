defmodule Arbiter.Agents do
  @moduledoc false

  use Boundary,
    deps: [Arbiter.Tenants],
    exports: [AgentRun]
end
