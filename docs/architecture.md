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
- Evaluate allow/deny decisions through `Arbiter.Policy.Engine`, which accepts DSL or parsed AST values.
- Enforce request subject/action/resource intent against the policy `allow` line when intent is provided.
- Authorize Gateway tool calls through a pure authorizer contract that separates RBAC allow/deny from ABAC retrieval scope construction.
- Normalize authorizer input through `Arbiter.Policy.AuthorizationRequest` before RBAC or ABAC decisions.
- Build decision reasons and policy scopes.
- Keep shared audit/decision reason identifiers in `Arbiter.Policy.DecisionReason`.
- Compile scopes into SQL predicates and vector metadata filters.
- Increment MVP policy versions through `Arbiter.Policy.Version`.

Boundary rule:

- Policy modules should not call `Arbiter.Repo`, HTTP clients, vector stores, clocks, ID generators, process messaging, or audit persistence.
- `Arbiter.Policy.Engine` is a pure facade over parsing and evaluation. It does not load policy bundles or execute external authorizers.
- Shared decision reasons are stable string identifiers because audit rows and lineage records persist them.
- `Arbiter.Policy.AuthorizationRequest` is the stable request contract for authorizers; plain maps and Gateway tool calls are normalized before request identity validation.
- Authorizer implementations in this boundary receive already-loaded request/user/role data and return `Arbiter.Policy.Decision` values. `Arbiter.Policy.Authorizer.Core` owns shared pure request identity validation, ABAC scope extraction, and decision shaping.
- Authorizers must fail closed when the request user id, loaded user snapshot id, or tenant scope do not match.

### Authorizer Shell Boundary

Owned by `Arbiter.Authorizers.*`.

Responsibilities:

- Provide `Arbiter.Authorizers.RepoBacked` for loading the current persisted user role and ABAC attributes from `Arbiter.Repo`.
- Provide `Arbiter.Authorizers.Casbin` as a backend-neutral Casbin port that calls an injected `enforce` function.
- Normalize Casbin requests into a tuple-like map with tenant/domain, subject, action, resource type, optional resource id, and object identifier before calling the enforcer.
- Keep Repo access and external policy engine calls out of `Arbiter.Policy` and `Arbiter.Gateway`.
- Reuse `Arbiter.Policy.Authorizer.Core` so Repo-backed, Casbin, and static authorizers share the same request identity and ABAC fail-close semantics.

Boundary rule:

- Repo-backed authorizers may call `Arbiter.Repo` and tenant schemas, but must return plain `Arbiter.Policy.Decision` values through the authorizer contract.
- Casbin authorizers must treat non-boolean enforcer responses, raised errors, thrown values, and timeouts as fail-closed errors.
- Gateway still receives authorizers as injected functions and must not directly know which authorizer shell is used.

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
- Fail closed when the injected authorizer raises or throws.
- Preserve safe authorizer error atoms as fail-closed audit reasons; unsafe error shapes are collapsed to `authorization_failed`.
- Optionally invoke an injected read model scope function to obtain accessible chunk ids for the current tenant, user, and policy version.
- Pass only Arbiter-guarded queries to retrieval tool adapters.
- Pass read model chunk allowlists to retrieval adapters through `GuardedQuery.allowed_chunk_ids` and fail closed if returned chunks ignore that allowlist.
- Return audit event data for persistence by the audit boundary.

Boundary rule:

- Gateway may orchestrate injected functions, but should not directly call Repo, vector stores, SaaS tools, HTTP clients, caches, clocks, or ID generators.
- Gateway does not emit telemetry directly; observed execution goes through `Arbiter.Observability.GatewayTelemetry`.
- Gateway receives an authorization function and must not directly own RBAC role lookup, ABAC attribute loading, policy storage, or external authorizer clients.

### Observability Boundary

Owned by `Arbiter.Observability.*`.

Responsibilities:

- Wrap Gateway tool calls when runtime telemetry is desired.
- Emit `[:arbiter, :gateway, :tool_call, :run]` telemetry with duration and chunk count measurements.
- Keep telemetry metadata bounded to status, decision, primary reason, tool, action, resource type, and policy version.
- Wrap audit persistence operations when runtime telemetry is desired.
- Emit `[:arbiter, :audit, :record, :run]` telemetry with duration and bounded operation status metadata.

Boundary rule:

- Observability modules may emit telemetry, but must not persist audit records or call Repo, policy stores, vector/search adapters, caches, HTTP clients, clocks, or ID generators.
- Gateway telemetry must not include tenant, user, agent run, query, prompt, chunk, payload, or row identifiers.
- Audit telemetry must not include tenant, user, agent run, answer, policy decision, query, chunk, payload, or row identifiers.

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

### Adapter Boundary

Owned by `Arbiter.Adapters.*`.

Responsibilities:

- Define adapter contracts for external or replaceable infrastructure.
- Provide `Arbiter.Adapters.Cache` as the cache invalidation behaviour.
- Provide `Arbiter.Adapters.Cache.Memory` for tests and local development.
- Provide `Arbiter.Adapters.Search` as the guarded retrieval search behaviour.
- Provide `Arbiter.Adapters.Search.Memory` for tests and local development.

Boundary rule:

- Adapter contracts should be backend-neutral and receive validated commands from orchestration boundaries.
- Search adapters must receive `Arbiter.Retrieval.GuardedQuery` values, not raw caller query maps, and must apply `allowed_chunk_ids` before returning chunks.
- Concrete cache, vector/search, SaaS, or HTTP clients should live behind this boundary or a narrower documented adapter boundary.

### Sync/Revoke and Outbox Consumer Boundary

Owned by `Arbiter.Sync.RevokeSimulation`, `Arbiter.Sync.Outbox`, `Arbiter.Sync.OutboxEvent`, `Arbiter.Sync.OutboxConsumerCommand`, `Arbiter.Sync.OutboxPayload`, `Arbiter.Sync.OutboxReadModelDispatch`, `Arbiter.Sync.OutboxCacheDispatch`, `Arbiter.Sync.OutboxConsumer`, `Arbiter.Sync.OutboxProcessor`, and `Arbiter.Sync.OutboxWorker`.

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
- Optionally schedule periodic bounded outbox processing through `Arbiter.Sync.OutboxWorker`; it is disabled by default and owns only process scheduling.
- Emit `[:arbiter, :sync, :outbox, :processor, :run]` telemetry for each processing pass with duration and aggregate row counts.
- Mark claimed rows as terminal only when the persisted `id`, `attempts`, `locked_at`, and optional `locked_by` still match the claimed row.
- Dispatch `invalidate_user_access_cache` events to `Arbiter.ReadModels.invalidate_user_access/4` so old `accessible_document_chunks` rows are invalidated after revoke.
- Dispatch `rebuild_user_access_projection` events to `Arbiter.ReadModels.rebuild_user_access_projection/4`, which invalidates old rows for the tenant/user/policy version and rebuilds active projections from current user and chunk state.
- Dispatch `invalidate_tool_result_cache` and `invalidate_retrieval_result_cache` events through configured cache adapters using validated tenant/user/policy-version scope.
- Fail read model rebuilds closed when the requested user source is missing, policy-version stale, or scope malformed.

Boundary rule:

- This boundary persists propagation commands as outbox rows and owns outbox status persistence. Real cache/process, vector, and search adapters should remain outside the policy and retrieval core.
- `Arbiter.Sync.OutboxConsumerCommand` must not call Repo, clocks, processes, cache adapters, or vector/search adapters. Callers pass timestamps in as data.
- `Arbiter.Sync.OutboxPayload` centralizes pure outbox payload validation and identity checks used by dispatch modules.
- `Arbiter.Sync.OutboxReadModelDispatch` must stay pure. It validates event payloads and returns read model commands, but does not call `Arbiter.Repo` or `Arbiter.ReadModels`.
- `Arbiter.Sync.OutboxCacheDispatch` must stay pure. It validates event payloads and returns cache adapter commands, but does not call adapters.
- `Arbiter.Sync.OutboxWorker` must not know read model or cache command details. It schedules `Arbiter.Sync.OutboxProcessor.run_once/2` with configured limits, intervals, and optional worker ownership.
- Outbox telemetry must not include tenant, user, aggregate, payload, or row identifiers; expose only pass status, limit, duration, and aggregate counts.

### Storage Strategy

Arbiter uses current-state CQRS rather than Event Sourcing.

- Command state lives in normalized PostgreSQL tables.
- Runtime read models and vector/search metadata are projections.
- Audit records are lineage, not replayable command state.
- Outbox rows are propagation commands, not the source of truth.
- Revoke paths use policy version bumps plus stale-snapshot fail-close behavior to avoid waiting for asynchronous projection refreshes.
- Outbox processing uses `pending -> processing -> processed | failed`; the current implementation provides both a bounded `run_once/2` processor and an optional supervised worker for implemented read model operations.
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

Arbiter uses the `:boundary` compiler to enforce the declared module groups
during compilation. Review the current groups with:

```sh
mix boundary.spec
```

Use built-in xref checks before adding new cross-module dependencies or when a
boundary violation needs dependency-shape debugging:

```sh
mix xref graph --format cycles --label compile-connected
mix xref graph --format stats --label compile-connected
```

Trace one file when a dependency looks suspicious:

```sh
mix xref trace lib/arbiter/gateway.ex --label compile
```

The current boundary configuration is documented in [Architecture Boundary Review](architecture-boundaries.md). New cache, vector/search, SaaS, or HTTP adapters should be added behind the existing boundary groups or a newly documented boundary group before production wiring.

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
