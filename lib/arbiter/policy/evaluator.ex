defmodule Arbiter.Policy.Evaluator do
  @moduledoc """
  Pure evaluator for parsed Arbiter policies.
  """

  alias Arbiter.Policy.AST
  alias Arbiter.Policy.Decision

  def evaluate(ast, context, opts \\ [])

  def evaluate(%AST{effect: :allow} = ast, context, opts) when is_map(context) do
    policy_version = Keyword.get(opts, :policy_version, "unknown")

    ast.conditions
    |> Enum.reduce_while([], fn condition, reasons ->
      case condition_satisfied?(condition, context) do
        {:ok, true} -> {:cont, [condition.reason | reasons]}
        {:ok, false} -> {:halt, {:deny, ["#{condition.reason}_failed"]}}
        {:error, _reason} -> {:halt, {:deny, ["evaluation_error"]}}
      end
    end)
    |> case do
      {:deny, reasons} ->
        deny(reasons, policy_version)

      reasons ->
        allow(Enum.reverse(reasons), policy_version, build_scope(context))
    end
  end

  def evaluate(_ast, _context, opts) do
    opts
    |> Keyword.get(:policy_version, "unknown")
    |> then(&deny(["evaluation_error"], &1))
  end

  defp condition_satisfied?(%{left: left, operator: operator, right: right}, context) do
    with {:ok, left_value} <- resolve(left, context),
         {:ok, right_value} <- resolve(right, context) do
      compare(left_value, operator, right_value)
    end
  end

  defp resolve({:literal, value}, _context), do: {:ok, value}

  defp resolve({:path, root, path}, context) do
    with {:ok, root_value} <- fetch_root(context, root) do
      fetch_path(root_value, path)
    end
  end

  defp fetch_root(context, "user"), do: fetch_map_value(context, :user, "user")
  defp fetch_root(context, "chunk"), do: fetch_map_value(context, :chunk, "chunk")
  defp fetch_root(context, root), do: fetch_map_value(context, root, root)

  defp fetch_path(value, []), do: {:ok, value}

  defp fetch_path(value, [field | rest]) do
    with {:ok, next_value} <- fetch_field(value, field) do
      fetch_path(next_value, rest)
    end
  end

  defp fetch_field(value, field) when is_map(value) do
    fetch_map_value(value, existing_atom(field), field)
  end

  defp fetch_field(_value, _field), do: {:error, :missing_attribute}

  defp fetch_map_value(map, nil, string_key) do
    case Map.fetch(map, string_key) do
      {:ok, nil} -> {:error, :missing_attribute}
      {:ok, value} -> {:ok, value}
      :error -> {:error, :missing_attribute}
    end
  end

  defp fetch_map_value(map, atom_key, string_key) do
    cond do
      Map.has_key?(map, atom_key) and not is_nil(Map.get(map, atom_key)) ->
        {:ok, Map.fetch!(map, atom_key)}

      Map.has_key?(map, string_key) and not is_nil(Map.get(map, string_key)) ->
        {:ok, Map.fetch!(map, string_key)}

      true ->
        {:error, :missing_attribute}
    end
  end

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
      %{
        "tenant_id" => tenant_id,
        "departments" => departments,
        "max_sensitivity" => clearance
      }
    else
      {:error, _reason} -> %{}
    end
  end

  defp allow(reasons, policy_version, scope) do
    %Decision{decision: :allow, reason: reasons, policy_version: policy_version, scope: scope}
  end

  defp deny(reasons, policy_version) do
    %Decision{decision: :deny, reason: reasons, policy_version: policy_version, scope: %{}}
  end

  defp existing_atom(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> nil
  end
end
