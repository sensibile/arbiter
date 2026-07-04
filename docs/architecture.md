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
- Optionally invoke an injected read model scope function to obtain accessible chunk ids for the current tenant, user, and policy version.
- Pass only Arbiter-guarded queries to retrieval tool adapters.
- Pass read model chunk allowlists to retrieval adapters through `GuardedQuery.allowed_chunk_ids` and fail closed if returned chunks ignore that allowlist.
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

### Read Model Boundary

Owned by `Arbiter.ReadModels`, `Arbiter.ReadModels.AccessibleDocumentChunk`, and `Arbiter.ReadModels.AccessibleDocumentChunkBuilder`.

Responsibilities:

- Persist `accessible_document_chunks` as the first runtime read model table.
- Store user-to-chunk accessibility by `tenant_id`, `user_id`, `chunk_id`, and `user_policy_version`.
- Build projection attributes from already-loaded user/chunk data and an allow policy decision through `Arbiter.ReadModels.AccessibleDocumentChunkBuilder`.
- Copy `chunk_policy_version` and `chunk_deleted_at` into the projection so retrieval can filter stale or deleted chunks without re-running command-side joins.
- Return active accessible chunk ids only when `tenant_id`, `user_id`, `user_policy_version`, `chunk_deleted_at IS NULL`, and `invalidated_at IS NULL` all match.
- Invalidate a user's old projection rows when revoke bumps that user's policy version.

Boundary rule:

- `Arbiter.ReadModels` owns Repo queries and updates for projection storage.
- `Arbiter.ReadModels.AccessibleDocumentChunkBuilder` must stay pure. It must not call Repo, clocks, vector stores, process workers, or external adapters.
- Policy, retrieval guard, and gateway modules should consume read model results through injected functions or orchestration layers rather than calling this boundary directly.
- `accessible_document_chunks` is derived storage. The command store remains authoritative, and stale, missing, deleted, or invalidated projection rows must not grant access.

### Sync/Revoke and Outbox Consumer Boundary

Owned by `Arbiter.Sync.RevokeSimulation`, `Arbiter.Sync.Outbox`, `Arbiter.Sync.OutboxEvent`, `Arbiter.Sync.OutboxConsumerCommand`, `Arbiter.Sync.OutboxReadModelDispatch`, `Arbiter.Sync.OutboxConsumer`, and `Arbiter.Sync.OutboxProcessor`.

Responsibilities:

- Simulate a user access revoke.
- Read the latest persisted user policy version.
- Bump the user policy version.
- Return cache invalidation commands for user access, tool results, and retrieval results.
- Persist outbox rows for those invalidation commands in the same transaction as the policy version bump.
- Return a revoke audit event shape.
- Decide outbox row state transitions as pure data through `Arbiter.Sync.OutboxConsumerCommand`.
- Claim available `pending` outbox rows and persist `processing`, `processed`, or `failed` status changes through `Arbiter.Sync.OutboxConsumer`.
- Run one bounded outbox processing pass through `Arbiter.Sync.OutboxProcessor.run_once/2`.
- Mark claimed rows as terminal only when the persisted `id`, `attempts`, and `locked_at` still match the claimed row.
- Dispatch `invalidate_user_access_cache` events to `Arbiter.ReadModels.invalidate_user_access/4` so old `accessible_document_chunks` rows are invalidated after revoke.

Boundary rule:

- This boundary persists propagation commands as outbox rows and owns outbox status persistence. Real cache/process adapters and background workers should remain outside the policy and retrieval core.
- `Arbiter.Sync.OutboxConsumerCommand` must not call Repo, clocks, processes, cache adapters, or vector/search adapters. Callers pass timestamps in as data.
- `Arbiter.Sync.OutboxReadModelDispatch` must stay pure. It validates event payloads and returns read model commands, but does not call `Arbiter.Repo` or `Arbiter.ReadModels`.

### Storage Strategy

Arbiter uses current-state CQRS rather than Event Sourcing.

- Command state lives in normalized PostgreSQL tables.
- Runtime read models and vector/search metadata are projections.
- Audit records are lineage, not replayable command state.
- Outbox rows are propagation commands, not the source of truth.
- Revoke paths use policy version bumps plus stale-snapshot fail-close behavior to avoid waiting for asynchronous projection refreshes.
- Outbox processing uses `pending -> processing -> processed | failed`; the current implementation provides a bounded `run_once/2` processor, not a supervised background worker.
- `accessible_document_chunks` is the first implemented read model table for retrieval filtering. Active lookups are scoped by tenant, user, user policy version, chunk deletion state, and revoke invalidation state.

## Fail-Closed Invariants

Arbiter currently tests these security invariants:

- Unauthorized chunks are excluded before they become prompt context.
- Caller-supplied retrieval filters are replaced by Arbiter scope filters.
- Caller-supplied read model allowlists are stripped before retrieval adapters execute.
- Retrieval adapter results must stay inside the injected read model chunk allowlist when one is provided.
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

The current boundary review is documented in [Architecture Boundary Review](architecture-boundaries.md). Based on the current `compile-connected` graph, `:boundary` should be deferred until the next external adapter or worker slice, but the proposed rules are now explicit.

## Infrastructure Tests

Default tests assume a reachable PostgreSQL database from local setup or CI service configuration.

Use Testcontainers-backed infrastructure tests when verifying that persistence boundaries work against a freshly started PostgreSQL container:

```sh
mix infra.test
```

Infrastructure tests live outside the default `test/` tree under `test_infra/` so `mix test` remains fast and does not require Docker.

Coverage has two explicit modes:

```sh
mix coverage.core
mix coverage.all
```

Use `mix coverage.core` while iterating on pure policy, retrieval, and gateway logic. It runs the fast suite and ignores shell, persistence, schema, and Phoenix scaffold modules so those intentionally separated boundaries do not appear as frequent 0% noise.

Use `mix coverage.all` at larger completion points or during periodic missing-test recovery. It runs both `test/` and `test_infra/` through Testcontainers and keeps the full module set in the report.
