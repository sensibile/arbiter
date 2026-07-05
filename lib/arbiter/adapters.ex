defmodule Arbiter.Adapters do
  @moduledoc false

  use Boundary,
    deps: [Arbiter.Retrieval],
    exports: [Cache, Search]
end
