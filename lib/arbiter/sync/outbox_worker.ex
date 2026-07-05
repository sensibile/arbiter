defmodule Arbiter.Sync.OutboxWorker do
  @moduledoc """
  Supervised worker for periodic bounded outbox processing.

  The worker owns process scheduling only. Claiming, command execution, and row
  state changes stay in `Arbiter.Sync.OutboxProcessor`.
  """

  use GenServer

  alias Arbiter.Sync.OutboxProcessor

  @default_interval_ms 5_000
  @default_limit 100

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    with {:ok, limit} <- positive_integer(opts, :limit, @default_limit),
         {:ok, interval_ms} <- positive_integer(opts, :interval_ms, @default_interval_ms),
         {:ok, processor} <- processor(opts) do
      processor_opts =
        opts
        |> Keyword.get(:processor_opts, [])
        |> maybe_put_worker_id(Keyword.get(opts, :worker_id))

      state = %{
        limit: limit,
        interval_ms: interval_ms,
        worker_id: Keyword.get(opts, :worker_id),
        processor: processor,
        processor_opts: processor_opts,
        timer_ref: nil,
        last_result: nil
      }

      {:ok, schedule_next(state)}
    end
  end

  @impl true
  def handle_info(:process_outbox, state) do
    result = state.processor.(state.limit, state.processor_opts)

    {:noreply, state |> Map.put(:last_result, result) |> schedule_next()}
  end

  defp positive_integer(opts, key, default) do
    value = Keyword.get(opts, key, default)

    case value do
      value when is_integer(value) and value > 0 -> {:ok, value}
      _invalid -> {:stop, {:invalid_outbox_worker_option, key}}
    end
  end

  defp processor(opts) do
    processor = Keyword.get(opts, :processor, &OutboxProcessor.run_once/2)

    if is_function(processor, 2) do
      {:ok, processor}
    else
      {:stop, {:invalid_outbox_worker_option, :processor}}
    end
  end

  defp maybe_put_worker_id(processor_opts, nil), do: processor_opts

  defp maybe_put_worker_id(processor_opts, worker_id),
    do: Keyword.put_new(processor_opts, :worker_id, worker_id)

  defp schedule_next(state) do
    timer_ref = Process.send_after(self(), :process_outbox, state.interval_ms)
    %{state | timer_ref: timer_ref}
  end
end
