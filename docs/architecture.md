# Arbiter Architecture

[한국어](architecture.ko.md)

This document summarizes the implemented MVP architecture. `ARBITER_DIRECTION.md` remains the product and architecture source of truth; this file tracks the current code contracts.

## MVP Status

The first MVP pass is implemented through the revoke simulation step:

1. Domain skeleton
2. Minimal Policy DSL
3. Scope compiler
4. Retrieval guard
5. Gateway
6. Audit lineage
7. Revoke simulation

The storage strategy is captured in [ADR 0001: Current-State CQRS With Transactional Outbox](adr/0001-state-sourced-cqrs.md).

## Module Boundaries

### Pure Policy Core

Owned by `Arbiter.Policy.*`.

Responsibilities:

- Parse minimal policy DSL into AST.
- Evaluate allow/deny decisions.
- Build decision reasons and policy scopes.
- Compile scopes into SQL predicates and vector metadata filters.
- Increment MVP policy versions through `Arbiter.Policy.Version`.

Boundary rule:

- Policy modules should not call `Arbiter.Repo`, HTTP clients, vector stores, clocks, ID generators, process messaging, or audit persistence.

### Retrieval Core

Owned by `Arbiter.Retrieval.*`.

Responsibilities:

- Force Arbiter vector metadata filters before retrieval execution.
- Strip caller-supplied filters from vector queries.
- Post-validate retrieved chunks against tenant, department, sensitivity, deletion, and policy version metadata.
- Return accepted/rejected chunk ids for lineage.

Boundary rule:

- Retrieval guard modules should not call vector stores directly. They return guarded queries and validation results for boundary modules to use.

### Gateway Orchestration

Owned by `Arbiter.Gateway`.

Responsibilities:

- Accept an agent `ToolCall`.
- Resolve the tool contract from an explicit registry.
- Invoke an injected authorization function.
- Fail closed on tenant scope mismatch, stale user policy snapshots, stale resource policy snapshots, invalid filters, tool failures, and retrieval validation failures.
- Pass only Arbiter-guarded queries to retrieval tool adapters.
- Return audit event data for persistence by the audit boundary.

Boundary rule:

- Gateway may orchestrate injected functions, but should not directly call Repo, vector stores, SaaS tools, HTTP clients, caches, clocks, or ID generators.

### Audit Boundary

Owned by `Arbiter.Audit`.

Responsibilities:

- Persist policy decision audit rows.
- Persist retrieval traces when retrieval happened or failed after scope/filter construction.
- Persist answer lineage to used chunks and policy decision ids.

Boundary rule:

- `Arbiter.Audit` owns Repo transactions for audit records. Policy decisions and retrieval guard results should already be shaped before entering this boundary.

### Sync/Revoke Boundary

Owned by `Arbiter.Sync.RevokeSimulation`, `Arbiter.Sync.Outbox`, and `Arbiter.Sync.OutboxEvent`.

Responsibilities:

- Simulate a user access revoke.
- Read the latest persisted user policy version.
- Bump the user policy version.
- Return cache invalidation commands for user access, tool results, and retrieval results.
- Persist outbox rows for those invalidation commands in the same transaction as the policy version bump.
- Return a revoke audit event shape.

Boundary rule:

- This boundary persists propagation commands as outbox rows. Real cache/process adapters and workers should remain outside the policy and retrieval core.

### Storage Strategy

Arbiter uses current-state CQRS rather than Event Sourcing.

- Command state lives in normalized PostgreSQL tables.
- Runtime read models and vector/search metadata are projections.
- Audit records are lineage, not replayable command state.
- Outbox rows are propagation commands, not the source of truth.
- Revoke paths use policy version bumps plus stale-snapshot fail-close behavior to avoid waiting for asynchronous projection refreshes.

## Fail-Closed Invariants

Arbiter currently tests these security invariants:

- Unauthorized chunks are excluded before they become prompt context.
- Caller-supplied retrieval filters are replaced by Arbiter scope filters.
- Retrieved chunks are post-validated against the decision policy version.
- Policy deny decisions do not execute tools.
- Tenant scope mismatch fails closed.
- Stale user/resource policy snapshots fail closed before tool execution.
- Revoke simulation invalidates cache keys and blocks old tool-call snapshots.
- Audit lineage records allow and deny decisions.

## Architecture Boundary Checks

Use built-in xref checks before adding new cross-module dependencies:

```sh
mix xref graph --format cycles --label compile-connected
mix xref graph --format stats --label compile-connected
```

Trace one file when a dependency looks suspicious:

```sh
mix xref trace lib/arbiter/gateway.ex --label compile
```

For stronger boundary enforcement, evaluate the `:boundary` library. It can define module groups, allowed dependencies, and exported modules, then report forbidden calls during compilation. A good first target would be preventing deep `Arbiter.Policy` and `Arbiter.Retrieval` modules from calling `Arbiter.Repo`.

## Infrastructure Tests

Default tests assume a reachable PostgreSQL database from local setup or CI service configuration.

Use Testcontainers-backed infrastructure tests when verifying that persistence boundaries work against a freshly started PostgreSQL container:

```sh
mix infra.test
```

Infrastructure tests live outside the default `test/` tree under `test_infra/` so `mix test` remains fast and does not require Docker.
