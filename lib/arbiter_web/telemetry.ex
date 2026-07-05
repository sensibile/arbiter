defmodule ArbiterWeb.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      # Telemetry poller will execute the given period measurements
      # every 10_000ms. Learn more here: https://telemetry-metrics.hexdocs.pm
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
      # Add reporters as children of your supervision tree.
      # {Telemetry.Metrics.ConsoleReporter, metrics: metrics()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # Phoenix Metrics
      summary("phoenix.endpoint.start.system_time",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.start.system_time",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.exception.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.socket_connected.duration",
        unit: {:native, :millisecond}
      ),
      sum("phoenix.socket_drain.count"),
      summary("phoenix.channel_joined.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.channel_handled_in.duration",
        tags: [:event],
        unit: {:native, :millisecond}
      ),

      # Database Metrics
      summary("arbiter.repo.query.total_time",
        unit: {:native, :millisecond},
        description: "The sum of the other measurements"
      ),
      summary("arbiter.repo.query.decode_time",
        unit: {:native, :millisecond},
        description: "The time spent decoding the data received from the database"
      ),
      summary("arbiter.repo.query.query_time",
        unit: {:native, :millisecond},
        description: "The time spent executing the query"
      ),
      summary("arbiter.repo.query.queue_time",
        unit: {:native, :millisecond},
        description: "The time spent waiting for a database connection"
      ),
      summary("arbiter.repo.query.idle_time",
        unit: {:native, :millisecond},
        description:
          "The time the connection spent waiting before being checked out for the query"
      ),

      # Arbiter Sync Metrics
      summary("arbiter.sync.outbox.processor.run.duration",
        tags: [:status],
        unit: {:native, :millisecond},
        description: "Duration of one bounded outbox processing pass"
      ),
      sum("arbiter.sync.outbox.processor.run.claimed",
        tags: [:status],
        description: "Outbox rows claimed by bounded processing passes"
      ),
      sum("arbiter.sync.outbox.processor.run.processed",
        tags: [:status],
        description: "Outbox rows marked processed by bounded processing passes"
      ),
      sum("arbiter.sync.outbox.processor.run.failed",
        tags: [:status],
        description: "Outbox rows marked failed by bounded processing passes"
      ),
      sum("arbiter.sync.outbox.processor.run.errors",
        tags: [:status],
        description: "Outbox rows or passes that ended in processor errors"
      ),

      # Arbiter Gateway Metrics
      summary("arbiter.gateway.tool_call.run.duration",
        tags: [:status, :decision, :tool, :action, :resource_type],
        unit: {:native, :millisecond},
        description: "Duration of one observed Gateway tool call"
      ),
      sum("arbiter.gateway.tool_call.run.retrieved_chunks",
        tags: [:status, :decision, :tool, :action, :resource_type],
        description: "Chunks returned by observed Gateway tool calls before post-validation"
      ),
      sum("arbiter.gateway.tool_call.run.accepted_chunks",
        tags: [:status, :decision, :tool, :action, :resource_type],
        description: "Chunks accepted by observed Gateway tool calls"
      ),
      sum("arbiter.gateway.tool_call.run.rejected_chunks",
        tags: [:status, :decision, :tool, :action, :resource_type],
        description: "Chunks rejected by observed Gateway tool calls"
      ),

      # VM Metrics
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io")
    ]
  end

  defp periodic_measurements do
    [
      # A module, function and arguments to be invoked periodically.
      # This function must call :telemetry.execute/3 and a metric must be added above.
      # {ArbiterWeb, :count_users, []}
    ]
  end
end
