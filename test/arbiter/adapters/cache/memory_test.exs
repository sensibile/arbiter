defmodule Arbiter.Adapters.Cache.MemoryTest do
  use ExUnit.Case, async: true

  alias Arbiter.Adapters.Cache
  alias Arbiter.Adapters.Cache.Memory

  test "invalidates entries by cache scope" do
    cache = start_supervised!({Memory, []})

    assert :ok =
             Memory.put(cache, "tool:old", :old,
               cache: :tool_result,
               tenant_id: "tenant-1",
               user_id: "user-1",
               previous_policy_version: "policy_v1"
             )

    assert :ok =
             Memory.put(cache, "tool:new", :new,
               cache: :tool_result,
               tenant_id: "tenant-1",
               user_id: "user-1",
               previous_policy_version: "policy_v2"
             )

    assert :ok =
             Cache.invalidate({Memory, cache}, %{
               cache: :tool_result,
               tenant_id: "tenant-1",
               user_id: "user-1",
               previous_policy_version: "policy_v1"
             })

    assert Memory.get(cache, "tool:old") == :miss
    assert Memory.get(cache, "tool:new") == {:ok, :new}
  end

  test "normalizes string tags and policy version aliases" do
    cache = start_supervised!({Memory, []})

    assert :ok =
             Memory.put(cache, "retrieval:old", :old, %{
               "cache" => :retrieval_result,
               "tenant_id" => "tenant-1",
               "user_id" => "user-1",
               "policy_version" => "policy_v1"
             })

    assert :ok =
             Cache.invalidate({Memory, cache}, %{
               "cache" => :retrieval_result,
               "tenant_id" => "tenant-1",
               "user_id" => "user-1",
               "previous_policy_version" => "policy_v1"
             })

    assert Memory.get(cache, "retrieval:old") == :miss
  end

  test "does not invalidate by partial cache scope" do
    cache = start_supervised!({Memory, []})

    assert :ok =
             Memory.put(cache, "tool:old", :old,
               cache: :tool_result,
               tenant_id: "tenant-1",
               user_id: "user-1",
               previous_policy_version: "policy_v1"
             )

    assert :ok =
             Cache.invalidate({Memory, cache}, %{
               cache: :tool_result,
               tenant_id: "tenant-1",
               user_id: "user-1"
             })

    assert Memory.get(cache, "tool:old") == {:ok, :old}
  end

  test "invalidates an explicit cache key" do
    cache = start_supervised!({Memory, []})

    assert :ok = Memory.put(cache, "retrieval:1", :value)
    assert :ok = Memory.put(cache, "retrieval:2", :other_value)

    assert :ok = Cache.invalidate({Memory, cache}, %{cache_key: "retrieval:1"})

    assert Memory.get(cache, "retrieval:1") == :miss
    assert Memory.get(cache, "retrieval:2") == {:ok, :other_value}
  end

  test "normalizes string cache key commands" do
    cache = start_supervised!({Memory, []})

    assert :ok = Memory.put(cache, "retrieval:1", :value)
    assert :ok = Cache.invalidate({Memory, cache}, %{"cache_key" => "retrieval:1"})

    assert Memory.get(cache, "retrieval:1") == :miss
  end

  test "preserves custom string tags while normalizing known tags" do
    cache = start_supervised!({Memory, []})

    assert :ok =
             Memory.put(cache, "retrieval:custom", :value, %{
               "cache" => :retrieval_result,
               "source" => "contracts"
             })

    assert :ok = Cache.invalidate({Memory, cache}, %{"source" => "contracts"})

    assert Memory.get(cache, "retrieval:custom") == {:ok, :value}
  end

  test "rejects invalid adapter references" do
    assert Cache.invalidate(:not_an_adapter, %{cache_key: "retrieval:1"}) ==
             {:error, :invalid_cache_adapter}
  end
end
