defmodule Arbiter.Adapters.Cache do
  @moduledoc """
  Cache adapter contract for invalidating derived propagation state.

  Implementations receive scoped invalidation commands rather than raw outbox
  rows. Commands must not include tenant/user payloads beyond the validated
  invalidation scope.
  """

  use Boundary,
    deps: [],
    exports: [Memory]

  @callback invalidate(target :: term(), command :: map()) :: :ok | {:error, term()}

  def invalidate({adapter, target}, command) when is_atom(adapter) and is_map(command) do
    adapter.invalidate(target, command)
  end

  def invalidate(_adapter, _command), do: {:error, :invalid_cache_adapter}
end
