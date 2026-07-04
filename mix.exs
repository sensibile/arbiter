defmodule Arbiter.MixProject do
  use Mix.Project

  def project do
    [
      app: :arbiter,
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      test_coverage: test_coverage(),
      aliases: aliases(),
      deps: deps(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Arbiter.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [
        precommit: :test,
        "infra.test": :test,
        "coverage.all": :test,
        "coverage.core": :test
      ]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.8.8"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},
      {:testcontainers, "~> 2.3", only: :test}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "infra.test": ["testcontainers.run test test_infra"],
      "coverage.core": ["cmd --shell MIX_ENV=test ARBITER_COVERAGE_MODE=core mix test --cover"],
      "coverage.all": ["testcontainers.run test -- --cover test test_infra"],
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end

  defp test_coverage do
    base = [summary: [threshold: 0]]

    if System.get_env("ARBITER_COVERAGE_MODE") == "core" do
      Keyword.put(base, :ignore_modules, core_coverage_ignored_modules())
    else
      base
    end
  end

  defp core_coverage_ignored_modules do
    [
      Arbiter,
      Arbiter.Application,
      Arbiter.Repo,
      ArbiterWeb,
      ArbiterWeb.Endpoint,
      ArbiterWeb.ErrorJSON,
      ArbiterWeb.Gettext,
      ArbiterWeb.Router,
      ArbiterWeb.Telemetry,
      Arbiter.Agents.AgentRun,
      Arbiter.Audit,
      Arbiter.Audit.AnswerLineage,
      Arbiter.Documents.Chunk,
      Arbiter.Documents.Document,
      Arbiter.Policy.Policy,
      Arbiter.Policy.PolicyDecision,
      Arbiter.ReadModels,
      Arbiter.ReadModels.AccessibleDocumentChunk,
      Arbiter.Retrieval.RetrievalTrace,
      Arbiter.Sync.Outbox,
      Arbiter.Sync.OutboxEvent,
      Arbiter.Sync.OutboxConsumer,
      Arbiter.Sync.OutboxProcessor,
      Arbiter.Sync.RevokeSimulation,
      Arbiter.SyncFixtures,
      Arbiter.Tenants.Group,
      Arbiter.Tenants.Membership,
      Arbiter.Tenants.Tenant,
      Arbiter.Tenants.User
    ]
  end
end
