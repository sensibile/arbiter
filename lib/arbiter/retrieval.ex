defmodule Arbiter.Retrieval do
  @moduledoc false

  use Boundary,
    deps: [Arbiter.Policy],
    exports: [Guard, GuardError, GuardResult, GuardedQuery, RetrievalTrace]
end
