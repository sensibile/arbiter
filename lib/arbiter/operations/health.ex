defmodule Arbiter.Operations.Health do
  @moduledoc """
  Operational health and readiness checks.

  Liveness is process-local and never calls external dependencies. Readiness is
  a boundary operation that checks database access and bounded outbox backlog
  counts for operators and deployment probes.
  """

  import Ecto.Query

  alias Arbiter.Repo
  alias Arbiter.Sync.OutboxEvent

  @outbox_statuses [
    OutboxEvent.status_pending(),
    OutboxEvent.status_processing(),
    OutboxEvent.status_failed()
  ]

  def liveness do
    %{
      status: "ok",
      checks: %{
        application: %{status: "ok"}
      }
    }
  end

  def readiness(opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)

    case database_check(repo) do
      :ok ->
        outbox = outbox_check(repo)

        %{
          status: "ready",
          checks: %{
            database: %{status: "ok"},
            outbox: outbox
          }
        }

      {:error, reason} ->
        %{
          status: "not_ready",
          checks: %{
            database: %{status: "error", reason: reason},
            outbox: %{status: "unknown"}
          }
        }
    end
  end

  def ready?(%{status: "ready"}), do: true
  def ready?(_readiness), do: false

  defp database_check(repo) when is_atom(repo) do
    case repo.query("SELECT 1", [], timeout: 1_000) do
      {:ok, _result} -> :ok
      {:error, _reason} -> {:error, "database_unavailable"}
    end
  rescue
    _exception -> {:error, "database_unavailable"}
  catch
    _kind, _reason -> {:error, "database_unavailable"}
  end

  defp database_check(_repo), do: {:error, "invalid_repo"}

  defp outbox_check(repo) do
    counts =
      @outbox_statuses
      |> Map.new(fn status -> {status, 0} end)
      |> Map.merge(outbox_counts(repo))

    %{
      status: "ok",
      pending: Map.fetch!(counts, OutboxEvent.status_pending()),
      processing: Map.fetch!(counts, OutboxEvent.status_processing()),
      failed: Map.fetch!(counts, OutboxEvent.status_failed())
    }
  end

  defp outbox_counts(repo) do
    OutboxEvent
    |> where([event], event.status in ^@outbox_statuses)
    |> group_by([event], event.status)
    |> select([event], {event.status, count(event.id)})
    |> repo.all(timeout: 1_000)
    |> Map.new()
  end
end
