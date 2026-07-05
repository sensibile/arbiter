defmodule Arbiter.Adapters.Search.MemoryTest do
  use ExUnit.Case, async: true

  alias Arbiter.Adapters.Search
  alias Arbiter.Adapters.Search.Memory
  alias Arbiter.Retrieval.GuardedQuery

  test "searches only with guarded queries" do
    search = start_supervised!({Memory, []})

    assert Search.search({Memory, search}, %{"text" => "renewal risk"}) ==
             {:error, :invalid_search_query}

    assert Search.search(:not_an_adapter, guarded_query()) == {:error, :invalid_search_adapter}
  end

  test "applies guarded filters and top k deterministically" do
    search =
      start_supervised!(
        {Memory,
         chunks: [
           chunk("chunk_1", department_id: "finance", sensitivity_level: 2),
           chunk("chunk_2", department_id: "legal", sensitivity_level: 1),
           chunk("chunk_3",
             tenant_id: "tenant_b",
             department_id: "finance",
             sensitivity_level: 2
           ),
           chunk("chunk_4", department_id: "sales", sensitivity_level: 1),
           chunk("chunk_5", department_id: "finance", sensitivity_level: 5),
           chunk("chunk_6", department_id: "finance", deleted_at: "2026-06-24T00:00:00Z")
         ]}
      )

    assert {:ok, chunks} = Search.search({Memory, search}, guarded_query(top_k: 1))
    assert Enum.map(chunks, & &1.id) == ["chunk_1"]
  end

  test "applies allowed chunk ids as an Arbiter-owned allowlist" do
    search =
      start_supervised!(
        {Memory,
         chunks: [
           chunk("chunk_1", department_id: "finance"),
           chunk("chunk_2", department_id: "legal"),
           chunk("chunk_3", department_id: "finance")
         ]}
      )

    query = guarded_query(allowed_chunk_ids: ["chunk_2", "chunk_3"])

    assert {:ok, chunks} = Search.search({Memory, search}, query)
    assert Enum.map(chunks, & &1.id) == ["chunk_2", "chunk_3"]
  end

  test "supports putting chunks after start and atom-keyed local fixtures" do
    search = start_supervised!({Memory, []})

    assert :ok =
             Memory.put(search, %{
               id: "chunk_1",
               tenant_id: "tenant_a",
               department_id: "finance",
               sensitivity_level: 2,
               deleted_at: nil,
               policy_version: "policy_v12"
             })

    assert {:ok, [%{id: "chunk_1"}]} =
             Search.search({Memory, search}, %{guarded_query() | query: %{text: "risk", top_k: 1}})
  end

  test "fails closed for malformed adapter-owned allowlists and unsupported filters" do
    search = start_supervised!({Memory, chunks: [chunk("chunk_1", department_id: "finance")]})

    assert Search.search({Memory, search}, guarded_query(allowed_chunk_ids: [""])) ==
             {:error, :invalid_allowed_chunk_ids}

    assert Search.search({Memory, search}, guarded_query(allowed_chunk_ids: "chunk_1")) ==
             {:error, :invalid_allowed_chunk_ids}

    assert Search.search({Memory, search}, %{guarded_query() | applied_filter: nil}) ==
             {:error, :invalid_search_filter}

    query = %{guarded_query() | applied_filter: %{"tenant_id" => %{"$unknown" => ["tenant_a"]}}}

    assert Search.search({Memory, search}, query) == {:error, :unsupported_search_filter}
  end

  test "builds a Gateway-compatible executor function" do
    search = start_supervised!({Memory, chunks: [chunk("chunk_1", department_id: "finance")]})
    execute = Search.executor({Memory, search})

    assert {:ok, [%{id: "chunk_1"}]} = execute.(guarded_query())
    assert execute.(%{"text" => "renewal risk"}) == {:error, :invalid_search_query}
  end

  defp guarded_query(opts \\ []) do
    %GuardedQuery{
      query: %{"text" => "renewal risk", "top_k" => Keyword.get(opts, :top_k, 10)},
      applied_filter: %{
        "tenant_id" => "tenant_a",
        "department_id" => %{"$in" => ["finance", "legal"]},
        "sensitivity_level" => %{"$lte" => 3},
        "deleted_at" => nil
      },
      policy_version: "policy_v12",
      allowed_chunk_ids: Keyword.get(opts, :allowed_chunk_ids)
    }
  end

  defp chunk(id, attrs) do
    attrs
    |> Keyword.put_new(:tenant_id, "tenant_a")
    |> Keyword.put_new(:department_id, "finance")
    |> Keyword.put_new(:sensitivity_level, 2)
    |> Keyword.put_new(:deleted_at, nil)
    |> Keyword.put_new(:policy_version, "policy_v12")
    |> Keyword.put(:id, id)
    |> Map.new()
  end
end
