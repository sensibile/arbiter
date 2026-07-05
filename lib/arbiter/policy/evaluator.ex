defmodule Arbiter.Policy.Evaluator do
  @moduledoc """
  Pure evaluator for parsed Arbiter policies.
  """

  alias Arbiter.Policy.AST
  alias Arbiter.Policy.Attributes
  alias Arbiter.Policy.Decision
  alias Arbiter.Policy.DecisionReason

  def evaluate(ast, context, opts \\ [])

  def evaluate(%AST{effect: :allow} = ast, context, opts) when is_map(context) do
    policy_version = Keyword.get(opts, :policy_version, "unknown")

    with :ok <- validate_intent(ast, context, opts) do
      ast.conditions
      |> Enum.reduce_while([], fn condition, reasons ->
        case condition_satisfied?(condition, context) do
          {:ok, true} -> {:cont, [condition.reason | reasons]}
          {:ok, false} -> {:halt, {:deny, [DecisionReason.failed(condition.reason)]}}
          {:error, _reason} -> {:halt, {:deny, [DecisionReason.evaluation_error()]}}
        end
      end)
      |> case do
        {:deny, reasons} ->
          deny(reasons, policy_version)

        reasons ->
          case build_scope(context) do
            {:ok, scope} -> allow(Enum.reverse(reasons), policy_version, scope)
            {:error, _reason} -> deny([DecisionReason.scope_compile_failed()], policy_version)
          end
      end
    else
      {:deny, reasons} -> deny(reasons, policy_version)
    end
  end

  def evaluate(_ast, _context, opts) do
    opts
    |> Keyword.get(:policy_version, "unknown")
    |> then(&deny([DecisionReason.evaluation_error()], &1))
  end

  defp validate_intent(%AST{} = ast, context, opts) do
    intent = %{
      subject: intent_value(:subject, context, opts),
      action: intent_value(:action, context, opts),
      resource: intent_value(:resource, context, opts)
    }

    cond do
      Enum.all?(Map.values(intent), &is_nil/1) ->
        :ok

      not Enum.all?(Map.values(intent), &valid_intent_value?/1) ->
        {:deny, [DecisionReason.policy_intent_missing()]}

      intent.subject == ast.subject and intent.action == ast.action and
          intent.resource == ast.resource ->
        :ok

      true ->
        {:deny, [DecisionReason.policy_intent_mismatch()]}
    end
  end

  defp intent_value(key, context, opts) do
    Keyword.get(opts, key) || Map.get(context, key) || Map.get(context, Atom.to_string(key))
  end

  defp valid_intent_value?(value), do: is_binary(value) and value != ""

  defp condition_satisfied?(%{left: left, operator: operator, right: right}, context) do
    with {:ok, left_value} <- resolve(left, context),
         {:ok, right_value} <- resolve(right, context) do
      compare(left_value, operator, right_value)
    end
  end

  defp resolve({:literal, value}, _context), do: {:ok, value}

  defp resolve({:path, root, path}, context) do
    with {:ok, root_value} <- fetch_root(context, root) do
      Attributes.fetch_path(root_value, path)
    end
  end

  defp fetch_root(context, root), do: Attributes.fetch_required(context, root)

  defp compare(left, :eq, right), do: {:ok, left == right}
  defp compare(left, :neq, right), do: {:ok, left != right}

  defp compare(left, :gt, right) when is_number(left) and is_number(right),
    do: {:ok, left > right}

  defp compare(left, :gte, right) when is_number(left) and is_number(right),
    do: {:ok, left >= right}

  defp compare(left, :lt, right) when is_number(left) and is_number(right),
    do: {:ok, left < right}

  defp compare(left, :lte, right) when is_number(left) and is_number(right),
    do: {:ok, left <= right}

  defp compare(left, :in, right) when is_list(right), do: {:ok, left in right}
  defp compare(_left, _operator, _right), do: {:error, :unsupported_comparison}

  defp build_scope(context) do
    with {:ok, tenant_id} <- resolve({:path, "user", ["tenant_id"]}, context),
         {:ok, departments} <- resolve({:path, "user", ["department_ids"]}, context),
         {:ok, clearance} <- resolve({:path, "user", ["clearance_level"]}, context) do
      {:ok,
       %{
         "tenant_id" => tenant_id,
         "departments" => departments,
         "max_sensitivity" => clearance
       }}
    end
  end

  defp allow(reasons, policy_version, scope) do
    %Decision{decision: :allow, reason: reasons, policy_version: policy_version, scope: scope}
  end

  defp deny(reasons, policy_version) do
    %Decision{decision: :deny, reason: reasons, policy_version: policy_version, scope: %{}}
  end
end
