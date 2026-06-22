defmodule Arbiter.Gateway do
  @moduledoc """
  Policy-aware gateway for agent tool calls.

  Contracts:

  * Input is a `ToolCall` plus explicit `:tools` and `:authorize` dependencies.
  * The module may not call Repo, vector stores, HTTP clients, clocks, ID
    generators, or audit persistence.
  * Policy, scope compilation, metadata filtering, and validation failures fail
    closed and return audit event data for the boundary layer to persist.
  * Retrieval tools must receive an Arbiter-guarded query, never the caller's
    raw filter.
  """

  alias Arbiter.Gateway.Error
  alias Arbiter.Gateway.Result
  alias Arbiter.Gateway.ToolCall
  alias Arbiter.Policy.Decision
  alias Arbiter.Retrieval.Guard

  def run_tool_call(%ToolCall{} = tool_call, opts) when is_list(opts) do
    tools = Keyword.fetch!(opts, :tools)
    authorize = Keyword.fetch!(opts, :authorize)

    with {:ok, tool} <- fetch_tool(tool_call, tools),
         {:ok, decision} <- authorize_call(tool_call, authorize),
         :ok <- validate_tenant_scope(tool_call, decision),
         :ok <- validate_policy_snapshots(tool_call, decision) do
      route_tool_call(tool_call, tool, decision)
    else
      {:deny, %Decision{} = decision} ->
        {:deny,
         %Result{
           tool_call: tool_call,
           policy_decision: decision,
           allowed_chunks: [],
           rejected_chunk_ids: [],
           audit_event: audit_event(tool_call, decision, status: "denied")
         }}

      {:error, %Error{} = error} ->
        {:error, error}
    end
  end

  def run_tool_call(_tool_call, _opts) do
    {:error,
     error(:invalid_tool_call, "tool call must be an Arbiter.Gateway.ToolCall", nil, nil,
       reason: ["invalid_tool_call"]
     )}
  end

  defp fetch_tool(%ToolCall{} = tool_call, tools) when is_map(tools) do
    case Map.fetch(tools, tool_call.tool) do
      {:ok, tool} -> validate_tool_contract(tool_call, tool)
      :error -> {:error, fail_closed(tool_call, nil, :unknown_tool, ["unknown_tool"])}
    end
  end

  defp fetch_tool(tool_call, _tools) do
    {:error, fail_closed(tool_call, nil, :invalid_tool_registry, ["invalid_tool_registry"])}
  end

  defp validate_tool_contract(
         tool_call,
         %{action: action, resource_type: resource_type, kind: kind} = tool
       )
       when action == tool_call.action and resource_type == tool_call.resource_type and
              kind in [:vector_retrieval] do
    if is_function(Map.get(tool, :execute), 1) do
      {:ok, tool}
    else
      {:error, fail_closed(tool_call, nil, :invalid_tool_contract, ["invalid_tool_contract"])}
    end
  end

  defp validate_tool_contract(tool_call, _tool) do
    {:error, fail_closed(tool_call, nil, :tool_contract_mismatch, ["tool_contract_mismatch"])}
  end

  defp authorize_call(tool_call, authorize) when is_function(authorize, 1) do
    case authorize.(tool_call) do
      {:ok, %Decision{decision: :allow} = decision} ->
        {:ok, decision}

      {:ok, %Decision{decision: :deny} = decision} ->
        {:deny, decision}

      {:error, _reason} ->
        {:error, fail_closed(tool_call, nil, :authorization_failed, ["authorization_failed"])}

      _other ->
        {:error, fail_closed(tool_call, nil, :authorization_failed, ["authorization_failed"])}
    end
  end

  defp authorize_call(tool_call, _authorize) do
    {:error, fail_closed(tool_call, nil, :authorization_failed, ["authorization_failed"])}
  end

  defp validate_tenant_scope(%ToolCall{} = tool_call, %Decision{} = decision) do
    if decision.scope["tenant_id"] == tool_call.tenant_id do
      :ok
    else
      {:error,
       fail_closed(tool_call, decision, :tenant_scope_mismatch, ["tenant_scope_mismatch"])}
    end
  end

  defp validate_policy_snapshots(%ToolCall{} = tool_call, %Decision{} = decision) do
    with :ok <-
           validate_snapshot_policy_version(
             tool_call,
             decision,
             tool_call.user_snapshot,
             :stale_user_policy_version
           ),
         :ok <-
           validate_snapshot_policy_version(
             tool_call,
             decision,
             tool_call.resource_snapshot,
             :stale_resource_policy_version
           ) do
      :ok
    end
  end

  defp validate_snapshot_policy_version(_tool_call, _decision, snapshot, _reason)
       when not is_map(snapshot),
       do: :ok

  defp validate_snapshot_policy_version(tool_call, decision, snapshot, reason) do
    case Map.get(snapshot, "policy_version", Map.get(snapshot, :policy_version)) do
      nil ->
        :ok

      policy_version when policy_version == decision.policy_version ->
        :ok

      _stale_policy_version ->
        {:error, fail_closed(tool_call, decision, reason, [Atom.to_string(reason)])}
    end
  end

  defp route_tool_call(tool_call, %{kind: :vector_retrieval, execute: execute}, decision) do
    with {:ok, guarded_query} <- Guard.guard_vector_query(tool_call.query, decision),
         {:ok, chunks} <- execute_guarded_query(execute, guarded_query),
         {:ok, guard_result} <- Guard.post_validate(chunks, decision),
         :ok <- ensure_usable_retrieval_result(tool_call, decision, guard_result) do
      {:ok,
       %Result{
         tool_call: tool_call,
         policy_decision: decision,
         allowed_chunks: guard_result.accepted_chunks,
         rejected_chunk_ids: guard_result.rejected_chunk_ids,
         audit_event: retrieval_audit_event(tool_call, decision, guard_result, "allowed")
       }}
    else
      {:error, %Error{} = error} ->
        {:error, error}

      {:error, reason} when is_atom(reason) ->
        {:error, fail_closed(tool_call, decision, reason, [Atom.to_string(reason)])}

      {:error, guard_error} ->
        {:error,
         fail_closed(tool_call, decision, guard_error.reason, [Atom.to_string(guard_error.reason)])}
    end
  end

  defp execute_guarded_query(execute, guarded_query) do
    try do
      case execute.(guarded_query) do
        {:ok, chunks} when is_list(chunks) ->
          {:ok, chunks}

        {:error, _reason} ->
          {:error, :tool_execution_failed}

        _other ->
          {:error, :tool_execution_failed}
      end
    rescue
      _exception -> {:error, :tool_execution_failed}
    catch
      _kind, _reason -> {:error, :tool_execution_failed}
    end
  end

  defp ensure_usable_retrieval_result(_tool_call, _decision, %{
         accepted_chunk_ids: [],
         rejected_chunk_ids: []
       }),
       do: :ok

  defp ensure_usable_retrieval_result(_tool_call, _decision, %{
         accepted_chunk_ids: accepted_chunk_ids
       })
       when accepted_chunk_ids != [],
       do: :ok

  defp ensure_usable_retrieval_result(tool_call, decision, guard_result) do
    {:error,
     fail_closed(
       tool_call,
       decision,
       :retrieval_validation_failed,
       ["retrieval_validation_failed"],
       guard_result: guard_result
     )}
  end

  defp fail_closed(tool_call, decision, reason, event_reasons, opts \\ []) do
    message = reason |> Atom.to_string() |> String.replace("_", " ")

    %Error{
      reason: reason,
      message: message,
      audit_event:
        audit_event(tool_call, decision,
          reason: event_reasons,
          status: "failed_closed",
          decision: "deny",
          guard_result: Keyword.get(opts, :guard_result)
        )
    }
  end

  defp error(reason, message, tool_call, decision, opts) do
    %Error{
      reason: reason,
      message: message,
      audit_event:
        audit_event(tool_call, decision,
          reason: Keyword.fetch!(opts, :reason),
          status: "failed_closed",
          decision: "deny"
        )
    }
  end

  defp retrieval_audit_event(tool_call, decision, guard_result, status) do
    audit_event(tool_call, decision, status: status, guard_result: guard_result)
  end

  defp audit_event(tool_call, decision, opts) do
    guard_result = Keyword.get(opts, :guard_result)

    %{
      event_type: "retrieval_decision",
      tenant_id: field(tool_call, :tenant_id),
      user_id: field(tool_call, :user_id),
      agent_run_id: field(tool_call, :agent_run_id),
      tool: field(tool_call, :tool),
      action: field(tool_call, :action),
      resource_type: field(tool_call, :resource_type),
      query: field(tool_call, :query) || %{},
      decision: Keyword.get(opts, :decision, decision_text(decision)),
      reason: Keyword.get(opts, :reason, reasons(decision)),
      policy_version: policy_version(decision),
      user_snapshot: field(tool_call, :user_snapshot) || %{},
      resource_snapshot: field(tool_call, :resource_snapshot) || %{},
      retrieved_chunk_ids: guard_field(guard_result, :retrieved_chunk_ids, []),
      accepted_chunk_ids: guard_field(guard_result, :accepted_chunk_ids, []),
      rejected_chunk_ids: guard_field(guard_result, :rejected_chunk_ids, []),
      applied_filter: guard_field(guard_result, :applied_filter, %{}),
      status: Keyword.fetch!(opts, :status)
    }
  end

  defp field(%ToolCall{} = tool_call, field), do: Map.fetch!(tool_call, field)
  defp field(_tool_call, _field), do: nil

  defp decision_text(%Decision{decision: decision}), do: Atom.to_string(decision)
  defp decision_text(_decision), do: "deny"

  defp reasons(%Decision{reason: reasons}), do: reasons
  defp reasons(_decision), do: []

  defp policy_version(%Decision{policy_version: policy_version}), do: policy_version
  defp policy_version(_decision), do: "unknown"

  defp guard_field(nil, _field, default), do: default
  defp guard_field(guard_result, field, _default), do: Map.fetch!(guard_result, field)
end
