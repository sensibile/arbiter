defmodule Arbiter.GatewayFixtures do
  use Boundary,
    top_level?: true,
    deps: [Arbiter]

  @moduledoc false

  alias Arbiter.Gateway.ToolCall
  alias Arbiter.Policy.Decision

  def tool_call(attrs \\ []) do
    struct!(ToolCall, Map.merge(tool_call_attrs(), Map.new(attrs)))
  end

  def tool_call_attrs(attrs \\ []) do
    Map.merge(
      %{
        tenant_id: "tenant_a",
        user_id: "user_123",
        agent_run_id: "run_456",
        tool: "semantic_search",
        action: "retrieve",
        resource_type: "document_chunk",
        query: %{"text" => "renewal risk"},
        user_snapshot: %{
          "id" => "user_123",
          "tenant_id" => "tenant_a",
          "department_ids" => ["finance", "legal"],
          "clearance_level" => 3,
          "policy_version" => "policy_v12"
        },
        resource_snapshot: %{"resource_type" => "document_chunk"}
      },
      Map.new(attrs)
    )
  end

  def allow_decision(attrs \\ []) do
    struct!(
      Decision,
      Map.merge(
        %{
          decision: :allow,
          reason: ["same_tenant", "active_user", "clearance_ok", "department_scope_matched"],
          policy_version: "policy_v12",
          scope: %{
            "tenant_id" => "tenant_a",
            "departments" => ["finance", "legal"],
            "max_sensitivity" => 3
          }
        },
        Map.new(attrs)
      )
    )
  end
end
