defmodule Arbiter.Application do
  use Boundary,
    top_level?: true,
    deps: [Arbiter, ArbiterWeb]

  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        ArbiterWeb.Telemetry,
        Arbiter.Repo,
        {DNSCluster, query: Application.get_env(:arbiter, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Arbiter.PubSub},
        outbox_worker_child(),
        # Start to serve requests, typically the last entry
        ArbiterWeb.Endpoint
      ]
      |> Enum.reject(&is_nil/1)

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Arbiter.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ArbiterWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp outbox_worker_child do
    opts = Application.get_env(:arbiter, Arbiter.Sync.OutboxWorker, [])

    if Keyword.get(opts, :enabled, false) do
      {Arbiter.Sync.OutboxWorker, Keyword.delete(opts, :enabled)}
    end
  end
end
