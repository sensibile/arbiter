defmodule Arbiter.Sync do
  @moduledoc false

  use Boundary,
    deps: [Arbiter.Adapters, Arbiter.Policy, Arbiter.ReadModels, Arbiter.Repo, Arbiter.Tenants],
    exports: [
      Outbox,
      OutboxCacheDispatch,
      OutboxConsumer,
      OutboxConsumerCommand,
      OutboxEvent,
      OutboxProcessor,
      OutboxReadModelDispatch,
      OutboxWorker,
      RevokeSimulation
    ]
end
