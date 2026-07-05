defmodule Arbiter.Adapters.Search.Memory do
  @moduledoc """
  In-memory search adapter for tests and local development.

  It applies the guarded metadata filter and optional `allowed_chunk_ids`
  allowlist before returning chunks. It is deterministic and does not rank by
  semantic similarity.
  """

  use GenServer

  alias Arbiter.Retrieval.GuardedQuery

  @behaviour Arbiter.Adapters.Search

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name)
    chunks = Keyword.get(opts, :chunks, [])
    GenServer.start_link(__MODULE__, chunks, name: name)
  end

  def put(server, chunk) when is_map(chunk) do
    GenServer.call(server, {:put, chunk})
  end

  @impl Arbiter.Adapters.Search
  def search(server, %GuardedQuery{} = query) do
    GenServer.call(server, {:search, query})
  end

  @impl true
  def init(chunks) when is_list(chunks), do: {:ok, chunks}

  @impl true
  def handle_call({:put, chunk}, _from, chunks) do
    {:reply, :ok, chunks ++ [chunk]}
  end

  def handle_call({:search, query}, _from, chunks) do
    result =
      with :ok <- validate_allowed_chunk_ids(query.allowed_chunk_ids),
           {:ok, filtered_chunks} <- filter_chunks(chunks, query) do
        {:ok, Enum.take(filtered_chunks, top_k(query.query))}
      end

    {:reply, result, chunks}
  end

  defp validate_allowed_chunk_ids(nil), do: :ok

  defp validate_allowed_chunk_ids(chunk_ids) when is_list(chunk_ids) do
    if Enum.all?(chunk_ids, &valid_chunk_id?/1) do
      :ok
    else
      {:error, :invalid_allowed_chunk_ids}
    end
  end

  defp validate_allowed_chunk_ids(_chunk_ids), do: {:error, :invalid_allowed_chunk_ids}

  defp filter_chunks(chunks, query) do
    Enum.reduce_while(chunks, {:ok, []}, fn chunk, {:ok, filtered_chunks} ->
      case chunk_matches?(chunk, query) do
        {:ok, true} -> {:cont, {:ok, [chunk | filtered_chunks]}}
        {:ok, false} -> {:cont, {:ok, filtered_chunks}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, filtered_chunks} -> {:ok, Enum.reverse(filtered_chunks)}
      error -> error
    end
  end

  defp chunk_matches?(chunk, %GuardedQuery{} = query) do
    with true <- allowed_chunk?(chunk, query.allowed_chunk_ids),
         {:ok, true} <- filter_matches?(chunk, query.applied_filter) do
      {:ok, true}
    else
      false -> {:ok, false}
      {:ok, false} -> {:ok, false}
      {:error, reason} -> {:error, reason}
    end
  end

  defp allowed_chunk?(_chunk, nil), do: true

  defp allowed_chunk?(chunk, allowed_chunk_ids) do
    case fetch(chunk, "id") do
      chunk_id when is_binary(chunk_id) -> chunk_id in allowed_chunk_ids
      _missing_or_invalid -> false
    end
  end

  defp filter_matches?(chunk, filter) when is_map(filter) do
    Enum.reduce_while(filter, {:ok, true}, fn
      {field, expected}, {:ok, true} ->
        case field_matches?(fetch(chunk, field), expected) do
          {:ok, true} -> {:cont, {:ok, true}}
          {:ok, false} -> {:halt, {:ok, false}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
    end)
  end

  defp filter_matches?(_chunk, _filter), do: {:error, :invalid_search_filter}

  defp field_matches?(value, %{"$in" => allowed_values}) when is_list(allowed_values),
    do: {:ok, value in allowed_values}

  defp field_matches?(value, %{"$lte" => max_value})
       when is_integer(value) and is_integer(max_value),
       do: {:ok, value <= max_value}

  defp field_matches?(_value, %{"$lte" => max_value}) when is_integer(max_value),
    do: {:ok, false}

  defp field_matches?(_value, %{}), do: {:error, :unsupported_search_filter}
  defp field_matches?(value, expected), do: {:ok, value == expected}

  defp top_k(query) when is_map(query) do
    case fetch(query, "top_k") do
      top_k when is_integer(top_k) and top_k > 0 -> top_k
      _missing_or_invalid -> 1_000_000
    end
  end

  defp top_k(_query), do: 1_000_000

  defp fetch(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key, Map.get(map, atom_key(key)))
  end

  defp fetch(map, key) when is_map(map), do: Map.get(map, key)

  defp atom_key("id"), do: :id
  defp atom_key("tenant_id"), do: :tenant_id
  defp atom_key("visibility"), do: :visibility
  defp atom_key("department_id"), do: :department_id
  defp atom_key("sensitivity_level"), do: :sensitivity_level
  defp atom_key("deleted_at"), do: :deleted_at
  defp atom_key("policy_version"), do: :policy_version
  defp atom_key("top_k"), do: :top_k
  defp atom_key(_key), do: nil

  defp valid_chunk_id?(chunk_id), do: is_binary(chunk_id) and chunk_id != ""
end
