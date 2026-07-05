defmodule Arbiter.Sync do
  @moduledoc false

  use Boundary,
    deps: [Arbiter.Policy, Arbiter.ReadModels, Arbiter.Repo, Arbiter.Tenants],
    exports: [
      Outbox,
      OutboxConsumer,
      OutboxConsumerCommand,
      OutboxEvent,
      OutboxProcessor,
      OutboxReadModelDispatch,
      OutboxWorker,
      RevokeSimulation
    ]
end
