defmodule Arbiter.Observability do
  @moduledoc false

  use Boundary,
    deps: [Arbiter.Gateway],
    exports: [GatewayTelemetry]
end
