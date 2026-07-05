defmodule Arbiter.Documents do
  @moduledoc false

  use Boundary,
    deps: [Arbiter.Tenants],
    exports: [Document, Chunk]
end
