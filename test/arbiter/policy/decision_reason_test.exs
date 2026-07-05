defmodule Arbiter.Policy.DecisionReasonTest do
  use ExUnit.Case, async: true

  alias Arbiter.Policy.DecisionReason

  test "exposes stable shared decision reason identifiers" do
    assert DecisionReason.rbac_allowed() == "rbac_allowed"
    assert DecisionReason.rbac_denied() == "rbac_denied"
    assert DecisionReason.tenant_scope_matched() == "tenant_scope_matched"
    assert DecisionReason.abac_scope_built() == "abac_scope_built"
    assert DecisionReason.active_user() == "active_user"
    assert DecisionReason.authorization_failed() == "authorization_failed"
    assert DecisionReason.clearance_ok() == "clearance_ok"
    assert DecisionReason.department_scope_matched() == "department_scope_matched"
    assert DecisionReason.evaluation_error() == "evaluation_error"
    assert DecisionReason.inactive_user() == "inactive_user"
    assert DecisionReason.policy_intent_mismatch() == "policy_intent_mismatch"
    assert DecisionReason.policy_intent_missing() == "policy_intent_missing"
    assert DecisionReason.same_tenant() == "same_tenant"
    assert DecisionReason.scope_compile_failed() == "scope_compile_failed"
    assert DecisionReason.source_matched() == "source_matched"
  end

  test "derives condition failure reason identifiers" do
    assert DecisionReason.failed("clearance_ok") == "clearance_ok_failed"
    assert DecisionReason.failed("") == "evaluation_error"
  end

  test "normalizes fail-closed error reasons for audit events" do
    assert DecisionReason.from_error(:stale_user_policy_version) == "stale_user_policy_version"
    assert DecisionReason.from_error("casbin_enforcer_timeout") == "casbin_enforcer_timeout"
    assert DecisionReason.from_error(nil) == "evaluation_error"
  end
end
