# Arbiter

[한국어](README.ko.md)

Arbiter is a policy-aware access gateway for Agentic RAG systems.

It ensures that AI agents can only retrieve, use, and cite data the current user is allowed to access.

## Current Scope

This repository is a Phoenix/Ecto implementation of the MVP described in `ARBITER_DIRECTION.md`.

The current implementation has completed the first MVP pass:

- Tenants, users, groups, and memberships
- Documents and chunks
- Policies and policy decisions
- Agent runs
- Retrieval traces
- Minimal policy DSL parsing and evaluation
- Scope compilation to SQL predicates and vector metadata filters
- Retrieval guard with pre-search filter injection and post-search validation
- Gateway orchestration for policy-aware tool calls
- Audit lineage persistence for policy decisions, retrieval traces, and answer lineage
- Revoke simulation with policy version bumping, transactional outbox invalidation commands, and stale snapshot fail-close
- Accessible chunk read model projection, rebuild execution, and optional supervised outbox processing
- Cache adapter contract with a local in-memory implementation for scoped outbox invalidation

See `docs/architecture.md` for the implemented module boundaries and contract summary.
See `docs/adr/0001-state-sourced-cqrs.md` for the storage strategy.

## Local Setup

Install the pinned local toolchain:

```sh
mise install
```

Run the local PostgreSQL dependency:

```sh
docker compose up -d db
```

Install dependencies, create the database, and migrate it:

```sh
mix setup
```

Run the test suite:

```sh
mix test
```

Run the project precommit check:

```sh
mix precommit
```

Run infrastructure tests with Testcontainers-managed PostgreSQL:

```sh
mix infra.test
```

Use core coverage while changing pure policy, retrieval, or gateway logic:

```sh
mix coverage.core
```

Use full coverage at larger completion points or when recovering missing tests across persistence boundaries:

```sh
mix coverage.all
```

`mix coverage.core` runs the fast suite and ignores shell, persistence, schema, and Phoenix scaffold modules. `mix coverage.all` runs both `test/` and `test_infra/` through Testcontainers and keeps the full module set in the report.

The app was generated API/domain-first without HTML/assets. If you start the endpoint, use:

```sh
mix phx.server
```

The default local database URL is `ecto://postgres:postgres@localhost:55432/arbiter_dev`.
Override it with `DATABASE_URL`; tests can use `TEST_DATABASE_URL`.

The supervised outbox worker is disabled by default. Enable it explicitly when
you want the app process to run bounded read model propagation passes:

```elixir
config :arbiter, Arbiter.Sync.OutboxWorker,
  enabled: true,
  worker_id: "worker-a",
  interval_ms: 5_000,
  limit: 100
```

`worker_id` is optional. When present, claimed outbox rows store it in
`locked_by` and terminal updates must match that ownership token.

Each outbox processing pass emits `[:arbiter, :sync, :outbox, :processor, :run]`
telemetry with duration, status, limit, and aggregate row counts only.

## Architecture Checks

Boundary enforcement runs during compilation through the `:boundary` compiler.
Use this when reviewing the declared boundary groups:

```sh
mix boundary.spec
```

Useful built-in dependency checks still help when investigating compile-time dependency shape:

```sh
mix xref graph --format cycles --label compile-connected
mix xref graph --format stats --label compile-connected
```

Use `mix xref trace path/to/file.ex --label compile` to investigate a specific compile-time dependency.

For adapter work, keep new cache, vector/search, and SaaS clients behind boundary modules. `mix compile --warnings-as-errors` fails when a forbidden boundary reference is introduced.
