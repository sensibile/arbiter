defmodule Arbiter.Policy.Version do
  @moduledoc """
  Minimal policy version helper for MVP revoke simulation.
  """

  @version_pattern ~r/^policy_v(?<version>\d+)$/

  def next("policy_v" <> _rest = policy_version) do
    case Regex.named_captures(@version_pattern, policy_version) do
      %{"version" => version} ->
        {:ok, "policy_v#{String.to_integer(version) + 1}"}

      nil ->
        {:error, :invalid_policy_version}
    end
  end

  def next(_policy_version), do: {:error, :invalid_policy_version}
end
