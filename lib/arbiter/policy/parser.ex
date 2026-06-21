defmodule Arbiter.Policy.Parser do
  @moduledoc """
  Parser for the minimal Arbiter Policy DSL.

  Supported MVP shape:

      policy "contract_chunk_read" {
        allow user retrieve chunk
        when user.tenant_id == chunk.tenant_id
         and user.status == "active"
         and chunk.department_id in user.department_ids
      }
  """

  alias Arbiter.Policy.AST
  alias Arbiter.Policy.ParseError
  alias Arbiter.Policy.Reasoner

  @policy_pattern ~r/^\s*policy\s+"([^"]+)"\s*\{\s*(.*?)\s*\}\s*$/s
  @allow_pattern ~r/^allow\s+([a-zA-Z_]\w*)\s+([a-zA-Z_]\w*)\s+([a-zA-Z_]\w*)$/
  @condition_pattern ~r/^(.+?)\s+(==|!=|>=|<=|>|<|in)\s+(.+)$/
  @path_pattern ~r/^([a-zA-Z_]\w*)((?:\.[a-zA-Z_]\w*)+)$/
  @string_pattern ~r/^"([^"]*)"$/

  @operators %{
    "==" => :eq,
    "!=" => :neq,
    ">=" => :gte,
    "<=" => :lte,
    ">" => :gt,
    "<" => :lt,
    "in" => :in
  }

  def parse(dsl) when is_binary(dsl) do
    with [name, body] <- Regex.run(@policy_pattern, dsl, capture: :all_but_first),
         {:ok, effect, subject, action, resource, condition_lines} <- parse_body(body),
         {:ok, conditions} <- parse_conditions(condition_lines) do
      {:ok,
       %AST{
         name: name,
         effect: effect,
         subject: subject,
         action: action,
         resource: resource,
         conditions: conditions
       }}
    else
      nil ->
        {:error, error(:invalid_policy, "expected policy \"name\" { ... }")}

      {:error, %ParseError{} = error} ->
        {:error, error}
    end
  end

  def parse(_dsl), do: {:error, error(:invalid_policy, "policy DSL must be a string")}

  defp parse_body(body) do
    lines =
      body
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    case lines do
      [allow_line | condition_lines] ->
        with [subject, action, resource] <-
               Regex.run(@allow_pattern, allow_line, capture: :all_but_first),
             {:ok, normalized_conditions} <- normalize_condition_lines(condition_lines) do
          {:ok, :allow, subject, action, resource, normalized_conditions}
        else
          nil -> {:error, error(:invalid_allow, "expected allow <subject> <action> <resource>")}
          {:error, %ParseError{} = error} -> {:error, error}
        end

      [] ->
        {:error, error(:invalid_policy, "policy body is empty")}
    end
  end

  defp normalize_condition_lines([]), do: {:ok, []}

  defp normalize_condition_lines([first | rest]) do
    with {:ok, first_condition} <- strip_prefix(first, "when "),
         {:ok, rest_conditions} <- strip_and_prefixes(rest) do
      {:ok, [first_condition | rest_conditions]}
    end
  end

  defp strip_and_prefixes(lines) do
    Enum.reduce_while(lines, {:ok, []}, fn line, {:ok, conditions} ->
      case strip_prefix(line, "and ") do
        {:ok, condition} -> {:cont, {:ok, [condition | conditions]}}
        {:error, %ParseError{} = error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, conditions} -> {:ok, Enum.reverse(conditions)}
      {:error, %ParseError{} = error} -> {:error, error}
    end
  end

  defp strip_prefix(line, prefix) do
    if String.starts_with?(line, prefix) do
      {:ok, String.trim_leading(line, prefix)}
    else
      {:error,
       error(:invalid_condition_prefix, "expected condition line to start with #{prefix}")}
    end
  end

  defp parse_conditions([]),
    do: {:error, error(:missing_conditions, "policy requires conditions")}

  defp parse_conditions(lines) do
    Enum.reduce_while(lines, {:ok, []}, fn line, {:ok, conditions} ->
      case parse_condition(line) do
        {:ok, condition} -> {:cont, {:ok, [condition | conditions]}}
        {:error, %ParseError{} = error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, conditions} -> {:ok, Enum.reverse(conditions)}
      {:error, %ParseError{} = error} -> {:error, error}
    end
  end

  defp parse_condition(line) do
    with [left, operator, right] <- Regex.run(@condition_pattern, line, capture: :all_but_first),
         {:ok, left_operand} <- parse_operand(String.trim(left)),
         {:ok, right_operand} <- parse_operand(String.trim(right)) do
      operator = Map.fetch!(@operators, operator)

      {:ok,
       %{
         left: left_operand,
         operator: operator,
         right: right_operand,
         reason: Reasoner.infer(left_operand, operator, right_operand)
       }}
    else
      nil -> {:error, error(:invalid_condition, "expected <left> <operator> <right>")}
      {:error, %ParseError{} = error} -> {:error, error}
    end
  end

  defp parse_operand(value) do
    cond do
      Regex.match?(@string_pattern, value) ->
        [literal] = Regex.run(@string_pattern, value, capture: :all_but_first)
        {:ok, {:literal, literal}}

      value in ["true", "false"] ->
        {:ok, {:literal, value == "true"}}

      Regex.match?(~r/^-?\d+$/, value) ->
        {integer, ""} = Integer.parse(value)
        {:ok, {:literal, integer}}

      Regex.match?(@path_pattern, value) ->
        [root, path] = Regex.run(@path_pattern, value, capture: :all_but_first)
        {:ok, {:path, root, String.split(String.trim_leading(path, "."), ".")}}

      true ->
        {:error, error(:invalid_operand, "unsupported operand: #{value}")}
    end
  end

  defp error(reason, message), do: %ParseError{reason: reason, message: message}
end
