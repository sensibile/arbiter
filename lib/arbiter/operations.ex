defmodule Arbiter.Operations do
  @moduledoc false

  use Boundary,
    deps: [Arbiter.Repo, Arbiter.Sync],
    exports: [Health]
end
