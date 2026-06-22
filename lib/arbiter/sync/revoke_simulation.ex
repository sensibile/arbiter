defmodule Arbiter.Sync.RevokeSimulation do
  @moduledoc """
  Small revoke-first simulation for the MVP.

  This boundary updates the user's policy version and returns cache invalidation
  commands for callers to execute through real cache/process adapters later.
  """

  alias Arbiter.Policy.Version
  alias Arbiter.Repo
  alias Arbiter.Tenants.User

  def revoke_user_access(user, opts \\ [])

  def revoke_user_access(%User{} = user, opts) do
    Repo.transaction(fn ->
      current_user = Repo.get!(User, user.id)

      case Version.next(current_user.policy_version) do
        {:ok, next_policy_version} ->
          updated_user =
            current_user
            |> User.changeset(%{policy_version: next_policy_version})
            |> Repo.update!()

          build_result(updated_user, current_user.policy_version, next_policy_version, opts)

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def revoke_user_access(_user, _opts), do: {:error, :invalid_user}

  defp build_result(user, previous_policy_version, current_policy_version, opts) do
    commands = invalidation_commands(user, previous_policy_version, current_policy_version)

    %{
      user: user,
      previous_policy_version: previous_policy_version,
      current_policy_version: current_policy_version,
      invalidation_commands: commands,
      audit_event: %{
        event_type: "access_revoked",
        tenant_id: user.tenant_id,
        user_id: user.id,
        reason: Keyword.get(opts, :reason, "access_revoked"),
        source: Keyword.get(opts, :source, "simulation"),
        previous_policy_version: previous_policy_version,
        current_policy_version: current_policy_version,
        invalidation_commands: commands
      }
    }
  end

  defp invalidation_commands(user, previous_policy_version, current_policy_version) do
    [
      command(
        :invalidate_user_access_cache,
        user,
        previous_policy_version,
        current_policy_version
      ),
      command(
        :invalidate_tool_result_cache,
        user,
        previous_policy_version,
        current_policy_version
      ),
      command(
        :invalidate_retrieval_result_cache,
        user,
        previous_policy_version,
        current_policy_version
      )
    ]
  end

  defp command(command, user, previous_policy_version, current_policy_version) do
    %{
      command: command,
      tenant_id: user.tenant_id,
      user_id: user.id,
      previous_policy_version: previous_policy_version,
      current_policy_version: current_policy_version
    }
  end
end
