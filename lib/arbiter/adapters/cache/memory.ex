defmodule Arbiter.Adapters.Cache.Memory do
  @moduledoc """
  In-memory cache adapter for tests and local development.

  Entries are tagged by cache name, tenant, user, and policy version so outbox
  invalidation commands can remove scoped derived data without a backend choice.
  """

  use GenServer

  @behaviour Arbiter.Adapters.Cache
  @scope_keys [:cache, :tenant_id, :user_id, :previous_policy_version]

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  def put(server, key, value, tags \\ %{})
      when is_binary(key) and (is_map(tags) or is_list(tags)) do
    GenServer.call(server, {:put, key, value, tags})
  end

  def get(server, key) when is_binary(key) do
    GenServer.call(server, {:get, key})
  end

  @impl Arbiter.Adapters.Cache
  def invalidate(server, command) when is_map(command) do
    GenServer.call(server, {:invalidate, command})
  end

  @impl true
  def init(_opts), do: {:ok, %{entries: %{}, invalidations: []}}

  @impl true
  def handle_call({:put, key, value, tags}, _from, state) do
    entry = %{value: value, tags: normalize_tags(tags)}
    {:reply, :ok, put_in(state.entries[key], entry)}
  end

  def handle_call({:get, key}, _from, state) do
    case Map.fetch(state.entries, key) do
      {:ok, %{value: value}} -> {:reply, {:ok, value}, state}
      :error -> {:reply, :miss, state}
    end
  end

  def handle_call({:invalidate, command}, _from, state) do
    command = normalize_tags(command)

    entries =
      Enum.reject(state.entries, fn {key, entry} ->
        invalidated_by_key?(key, command) or invalidated_by_scope?(entry.tags, command)
      end)
      |> Map.new()

    state = %{state | entries: entries, invalidations: [command | state.invalidations]}
    {:reply, :ok, state}
  end

  defp invalidated_by_key?(key, %{cache_key: cache_key}) when is_binary(cache_key),
    do: key == cache_key

  defp invalidated_by_key?(_key, _command), do: false

  defp invalidated_by_scope?(tags, command) do
    Enum.all?(@scope_keys, &Map.has_key?(command, &1)) and
      Enum.all?(@scope_keys, fn key ->
        Map.get(tags, key) == Map.get(command, key)
      end)
  end

  defp normalize_tags(map) do
    Map.new(map, fn
      {key, value} when is_binary(key) -> {normalize_key(key), value}
      {key, value} -> {key, value}
    end)
  end

  defp normalize_key("cache"), do: :cache
  defp normalize_key("tenant_id"), do: :tenant_id
  defp normalize_key("user_id"), do: :user_id
  defp normalize_key("previous_policy_version"), do: :previous_policy_version
  defp normalize_key("policy_version"), do: :previous_policy_version
  defp normalize_key("cache_key"), do: :cache_key
  defp normalize_key(key), do: key
end
