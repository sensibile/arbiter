defmodule Arbiter do
  use Boundary,
    top_level?: true,
    deps: [],
    exports: [
      Agents,
      Adapters,
      Authorizers,
      Audit,
      Documents,
      Gateway,
      Observability,
      Operations,
      Policy,
      ReadModels,
      Repo,
      Retrieval,
      Sync,
      Tenants
    ]

  @moduledoc """
  Arbiter keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  def health_liveness, do: Arbiter.Operations.Health.liveness()
  def health_readiness(opts \\ []), do: Arbiter.Operations.Health.readiness(opts)
  def health_ready?(readiness), do: Arbiter.Operations.Health.ready?(readiness)
end
