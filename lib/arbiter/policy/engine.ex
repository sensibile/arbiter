defmodule Arbiter.Policy.Engine do
  @moduledoc """
  Facade for evaluating Arbiter policy DSL or parsed AST values.

  The engine stays pure: it parses and evaluates policy data already supplied by
  the caller, and returns a decision or a parse error. Persistence, policy bundle
  loading, clocks, IDs, and external authorizers belong to shell boundaries.
  """

  alias Arbiter.Policy.AST
  alias Arbiter.Policy.Evaluator
  alias Arbiter.Policy.Parser

  def evaluate(policy, context, opts \\ [])

  def evaluate(dsl, context, opts) when is_binary(dsl) and is_map(context) do
    with {:ok, ast} <- Parser.parse(dsl) do
      {:ok, Evaluator.evaluate(ast, context, opts)}
    end
  end

  def evaluate(%AST{} = ast, context, opts) when is_map(context) do
    {:ok, Evaluator.evaluate(ast, context, opts)}
  end

  def evaluate(_policy, _context, _opts), do: {:error, :invalid_policy_engine_input}
end
