defmodule Arbiter.Adapters.Search do
  @moduledoc """
  Search adapter contract for executing guarded retrieval queries.

  Implementations receive `Arbiter.Retrieval.GuardedQuery` values only. Raw
  caller query maps must be guarded before reaching this boundary.
  """

  use Boundary,
    deps: [Arbiter.Retrieval],
    exports: [Memory]

  alias Arbiter.Retrieval.GuardedQuery

  @callback search(target :: term(), query :: GuardedQuery.t()) ::
              {:ok, list()} | {:error, term()}

  def search({adapter, target}, %GuardedQuery{} = query) when is_atom(adapter) do
    adapter.search(target, query)
  end

  def search({_adapter, _target}, _query), do: {:error, :invalid_search_query}
  def search(_adapter, _query), do: {:error, :invalid_search_adapter}

  def executor(adapter) do
    fn
      %GuardedQuery{} = query -> search(adapter, query)
      _query -> {:error, :invalid_search_query}
    end
  end
end
