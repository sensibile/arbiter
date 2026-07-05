defmodule Arbiter do
  use Boundary,
    top_level?: true,
    deps: [],
    exports: [
      Agents,
      Adapters,
      Audit,
      Documents,
      Gateway,
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
end
