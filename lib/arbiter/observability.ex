defmodule Arbiter.Observability do
  @moduledoc false

  use Boundary,
    deps: [Arbiter.Audit, Arbiter.Gateway],
    exports: [AuditTelemetry, GatewayTelemetry]
end
