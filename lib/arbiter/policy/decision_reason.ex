defmodule Arbiter.Policy.DecisionReason do
  @moduledoc """
  Stable policy decision reason identifiers.

  Decision reasons are persisted into audit rows and lineage records, so modules
  should use this catalog instead of open-coded strings for shared reasons.
  """

  @abac_scope_built "abac_scope_built"
  @active_user "active_user"
  @authorization_failed "authorization_failed"
  @clearance_ok "clearance_ok"
  @department_scope_matched "department_scope_matched"
  @evaluation_error "evaluation_error"
  @inactive_user "inactive_user"
  @policy_intent_mismatch "policy_intent_mismatch"
  @policy_intent_missing "policy_intent_missing"
  @rbac_allowed "rbac_allowed"
  @rbac_denied "rbac_denied"
  @same_tenant "same_tenant"
  @scope_compile_failed "scope_compile_failed"
  @source_matched "source_matched"
  @tenant_scope_matched "tenant_scope_matched"

  def abac_scope_built, do: @abac_scope_built
  def active_user, do: @active_user
  def authorization_failed, do: @authorization_failed
  def clearance_ok, do: @clearance_ok
  def department_scope_matched, do: @department_scope_matched
  def evaluation_error, do: @evaluation_error
  def inactive_user, do: @inactive_user
  def policy_intent_mismatch, do: @policy_intent_mismatch
  def policy_intent_missing, do: @policy_intent_missing
  def rbac_allowed, do: @rbac_allowed
  def rbac_denied, do: @rbac_denied
  def same_tenant, do: @same_tenant
  def scope_compile_failed, do: @scope_compile_failed
  def source_matched, do: @source_matched
  def tenant_scope_matched, do: @tenant_scope_matched

  def failed(reason) when is_binary(reason) and reason != "", do: "#{reason}_failed"
  def failed(_reason), do: @evaluation_error

  def from_error(nil), do: @evaluation_error
  def from_error(reason) when is_atom(reason), do: Atom.to_string(reason)
  def from_error(reason) when is_binary(reason) and reason != "", do: reason
  def from_error(_reason), do: @evaluation_error
end
