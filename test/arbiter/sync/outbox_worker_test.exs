defmodule Arbiter.Sync.OutboxWorkerTest do
  use ExUnit.Case, async: true

  alias Arbiter.Sync.OutboxWorker

  @interval_ms :timer.hours(1)

  test "runs the injected processor when the work message is received" do
    parent = self()

    processor = fn limit, opts ->
      send(parent, {:processed_outbox, limit, opts})
      {:ok, %{claimed: 0, processed: 0, failed: 0, errors: 0, results: []}}
    end

    pid =
      start_supervised!(
        {OutboxWorker,
         name: unique_name(),
         limit: 7,
         interval_ms: @interval_ms,
         processor: processor,
         processor_opts: [now: ~U[2026-06-24 03:00:00Z]]}
      )

    send(pid, :process_outbox)

    assert_receive {:processed_outbox, 7, [now: ~U[2026-06-24 03:00:00Z]]}
    assert %{last_result: {:ok, %{claimed: 0}}, timer_ref: timer_ref} = :sys.get_state(pid)
    assert is_reference(timer_ref)
  end

  test "stores processor errors without crashing" do
    processor = fn _limit, _opts -> {:error, :database_unavailable} end

    pid =
      start_supervised!(
        {OutboxWorker,
         name: unique_name(), limit: 1, interval_ms: @interval_ms, processor: processor}
      )

    send(pid, :process_outbox)
    assert %{last_result: {:error, :database_unavailable}} = :sys.get_state(pid)
  end

  test "passes configured worker ownership to the processor" do
    parent = self()

    processor = fn _limit, opts ->
      send(parent, {:processor_opts, opts})
      {:ok, %{claimed: 0}}
    end

    pid =
      start_supervised!(
        {OutboxWorker,
         name: unique_name(),
         limit: 1,
         interval_ms: @interval_ms,
         worker_id: "worker-a",
         processor: processor,
         processor_opts: [now: ~U[2026-06-24 03:00:00Z]]}
      )

    send(pid, :process_outbox)

    assert_receive {:processor_opts, opts}
    assert Keyword.fetch!(opts, :now) == ~U[2026-06-24 03:00:00Z]
    assert Keyword.fetch!(opts, :worker_id) == "worker-a"
  end

  test "does not override an explicit processor worker id" do
    parent = self()

    processor = fn _limit, opts ->
      send(parent, {:processor_opts, opts})
      {:ok, %{claimed: 0}}
    end

    pid =
      start_supervised!(
        {OutboxWorker,
         name: unique_name(),
         limit: 1,
         interval_ms: @interval_ms,
         worker_id: "worker-a",
         processor: processor,
         processor_opts: [worker_id: "processor-worker"]}
      )

    send(pid, :process_outbox)

    assert_receive {:processor_opts, [worker_id: "processor-worker"]}
  end

  test "rejects invalid scheduling options" do
    assert {:error, {{:invalid_outbox_worker_option, :limit}, _child}} =
             start_supervised(
               {OutboxWorker,
                name: unique_name(), limit: 0, interval_ms: @interval_ms, processor: no_op()}
             )

    assert {:error, {{:invalid_outbox_worker_option, :interval_ms}, _child}} =
             start_supervised(
               {OutboxWorker, name: unique_name(), limit: 1, interval_ms: 0, processor: no_op()}
             )

    assert {:error, {{:invalid_outbox_worker_option, :processor}, _child}} =
             start_supervised(
               {OutboxWorker,
                name: unique_name(),
                limit: 1,
                interval_ms: @interval_ms,
                processor: :not_a_function}
             )
  end

  defp no_op, do: fn _limit, _opts -> {:ok, %{claimed: 0}} end

  defp unique_name do
    :"#{__MODULE__}-#{System.unique_integer([:positive])}"
  end
end
