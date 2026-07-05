defmodule ArbiterWeb.TelemetryTest do
  use ExUnit.Case, async: true

  alias ArbiterWeb.Telemetry

  test "gateway metrics expose only bounded tags" do
    gateway_metrics =
      Telemetry.metrics()
      |> Enum.filter(fn metric ->
        match?([:arbiter, :gateway, :tool_call, :run | _rest], metric.name)
      end)

    assert Enum.map(gateway_metrics, & &1.name) == [
             [:arbiter, :gateway, :tool_call, :run, :duration],
             [:arbiter, :gateway, :tool_call, :run, :retrieved_chunks],
             [:arbiter, :gateway, :tool_call, :run, :accepted_chunks],
             [:arbiter, :gateway, :tool_call, :run, :rejected_chunks]
           ]

    allowed_tags = [:status, :decision, :tool, :action, :resource_type]
    forbidden_tags = [:tenant_id, :user_id, :agent_run_id, :query, :chunk_id, :chunk_ids]

    assert Enum.all?(gateway_metrics, &(&1.tags == allowed_tags))

    assert Enum.all?(
             gateway_metrics,
             &MapSet.disjoint?(MapSet.new(&1.tags), MapSet.new(forbidden_tags))
           )
  end
end
