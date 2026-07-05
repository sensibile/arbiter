# ADR 0001: Current-State CQRS With Transactional Outbox

[한국어](0001-state-sourced-cqrs.ko.md)

## Status

Accepted

## Context

Arbiter has two very different traffic profiles:

- Admin and sync workflows need to handle complex policy, tenant, user, group, membership, ACL, and classification changes.
- Gateway and retrieval workflows need fast, stable reads under high traffic.

CQRS is required because hot-path authorization and retrieval should not repeatedly join normalized admin tables, parse policy DSL, or rebuild user scopes on every request.

Event Sourcing is not a good fit for the current MVP because Arbiter needs low-latency fail-closed authorization. Reconstructing security-sensitive current state from an event stream would add latency and operational risk to hot paths. Audit and propagation events are still useful, but they should not be the source of truth for runtime state.

## Decision

Arbiter uses **current-state CQRS with transactional outbox**.

- PostgreSQL current-state tables are the source of truth.
- Runtime read models are projections derived from the current state.
- Search/vector metadata is a projection, not the source of truth.
- Audit logs are lineage records, not command-state reconstruction logs.
- Outbox rows are propagation commands, not event-sourced state.
- Revoke paths bump policy versions and write invalidation commands in the same transaction.
- Gateway and retrieval paths fail closed when policy versions or projections are stale.

## Storage Model

### Command Store

Normalized PostgreSQL tables own current state:

- tenants
- users
- groups
- memberships
- documents
- chunks
- policies
- policy decisions where relevant to audit

### Runtime Read Model

Future projection tables should optimize gateway and retrieval reads:

- user access projections
- policy scope projections
- tool permission projections
- chunk access metadata projections

Projection keys must include tenant and policy-version context, such as `tenant_id`, `user_id`, `policy_version`, and resource/action dimensions.

The read model storage contract is:

| Write-side change | Outbox command | Command status | Read model target | Lookup shape |
| --- | --- | --- | --- | --- |
| User membership, role, status, clearance, or policy-version change | `invalidate_user_access_cache` | Implemented MVP command | User access projection table/cache | `tenant_id`, `user_id`, `policy_version` |
| User membership, role, status, clearance, or policy-version change | `rebuild_user_access_projection` | Implemented MVP command/executor | User access projection table/cache | `tenant_id`, `user_id`, `policy_version` |
| Policy DSL, policy version, or scope-relevant tenant setting change | `rebuild_policy_scope_projection` | Planned projection command | Policy scope projection table/cache | `tenant_id`, `policy_id`, `resource_type`, `action`, `policy_version` |
| Tool permission or tool contract change | `invalidate_tool_result_cache` | Implemented MVP command | Tool permission projection/cache | `tenant_id`, `user_id`, `tool`, `action`, `policy_version` |
| Tool permission or tool contract change | `rebuild_tool_permission_projection` | Planned projection command | Tool permission projection/cache | `tenant_id`, `user_id`, `tool`, `action`, `policy_version` |
| Document, chunk, ACL, classification, deletion, or metadata change | `invalidate_retrieval_result_cache` | Implemented MVP command | Chunk access metadata table and vector/search metadata index | `tenant_id`, `chunk_id`, `document_id`, `policy_version`, access metadata |
| Document, chunk, ACL, classification, deletion, or metadata change | `refresh_chunk_access_metadata` | Planned projection command | Chunk access metadata table and vector/search metadata index | `tenant_id`, `chunk_id`, `document_id`, `policy_version`, access metadata |

Gateway and retrieval code may read from projection tables, vector metadata, and cache entries only when the tenant and policy-version context matches the current command-store state or a trusted snapshot. A missing, stale, or failed projection is a deny/fail-closed condition for security-sensitive reads.

Projection tables and caches are derived storage. They may be rebuilt from command-state tables, and they must not introduce access grants that are absent from the command store.

The first implemented read model table is `accessible_document_chunks`. It stores active user-to-chunk access snapshots keyed by tenant, user, chunk, and user policy version. Retrieval lookups must filter on tenant, user, user policy version, `chunk_deleted_at IS NULL`, and `invalidated_at IS NULL`.

The first gateway integration is intentionally small: `Arbiter.Gateway` accepts an injected read model scope function and passes the returned chunk ids to retrieval adapters through `GuardedQuery.allowed_chunk_ids`. Gateway does not call `Arbiter.ReadModels` or `Arbiter.Repo` directly. If the provider is unavailable, returns an invalid shape, returns an empty scope, or the retrieval adapter returns chunks outside the allowlist, Gateway fails closed.

### Audit and Lineage

Audit tables record what happened:

- policy decisions
- retrieval traces
- answer lineages
- revoke events when added

They support explainability and compliance. They are not used to replay command state.

### Transactional Outbox

Outbox tables record propagation work:

- cache invalidation
- projection rebuild requests
- vector/search metadata refresh requests

Outbox rows are written in the same database transaction as the current-state change that requires them.

Outbox processing follows a small state machine:

```text
pending
→ processing
→ processed | failed
```

The outbox consumer boundary claims available `pending` rows, marks them `processing` with a lock timestamp and incremented attempt count, executes the matching projection/cache/index adapter, then marks the row `processed` or `failed`. The pure consumer command decides the next row state; the Repo boundary owns row locking, transactions, and persistence.

Terminal marking must prove claim ownership. The current implementation uses the claimed row's `id`, `attempts`, `locked_at`, and optional `locked_by` as the ownership token.

Projection/cache/index adapters invoked by the outbox consumer must be idempotent. Reprocessing an equivalent command must converge on the same read model state, because the outbox is an at-least-once propagation mechanism.

## Revoke-First Rule

Grant and revoke are treated differently.

- Grant can tolerate short projection delay because the user may temporarily see less.
- Revoke cannot tolerate stale access because it may leak data.

For revoke:

```text
admin revoke command
→ update current state
→ bump policy version
→ write invalidation outbox rows
→ commit
→ gateway rejects stale policy snapshots
→ workers refresh projections and caches
```

## Consequences

Benefits:

- Hot paths read stable projections instead of complex admin state.
- Current state remains easy to inspect and mutate transactionally.
- Revoke safety does not depend on asynchronous projection completion.
- Outbox rows make propagation retryable without adopting Event Sourcing.

Tradeoffs:

- Projection freshness must be monitored.
- The optional outbox worker can drive implemented read model operations, but production still needs real cache/vector/search adapters and observability.
- Duplicate derived state must be validated against versioning rules.
- Outbox processing needs idempotency and retry semantics.

## Implementation Notes

The MVP currently includes:

- `Arbiter.Sync.RevokeSimulation` for user policy version bumps.
- `Arbiter.Sync.OutboxEvent` for persisted propagation commands.
- `Arbiter.Sync.Outbox` for shaping invalidation command changesets.
- `Arbiter.ReadModels.AccessibleDocumentChunk` for the first retrieval read model projection table.
- `Arbiter.ReadModels.AccessibleDocumentChunkBuilder` for pure user/chunk/decision-to-projection attribute shaping.
- `Arbiter.ReadModels` for projection upsert, active lookup, and user-policy invalidation.
- `Arbiter.Sync.OutboxReadModelDispatch` for mapping user-access invalidation and rebuild outbox events to read model commands.
- `Arbiter.Sync.OutboxCacheDispatch` for mapping tool and retrieval cache invalidation events to backend-neutral cache adapter commands.
- `Arbiter.Adapters.Cache` and `Arbiter.Adapters.Cache.Memory` for scoped cache invalidation through a replaceable adapter contract.
- `Arbiter.Adapters.Search` and `Arbiter.Adapters.Search.Memory` for guarded retrieval execution through a replaceable adapter contract.
- `Arbiter.Sync.OutboxProcessor.run_once/2` for one bounded pass that claims pending outbox rows, dispatches supported read model commands, and marks rows processed or failed.
- `Arbiter.Sync.OutboxWorker` for optional supervised scheduling of bounded outbox processing passes.
- Optional `locked_by` outbox ownership for worker-visible claim provenance and terminal update checks.
- Outbox processor telemetry on `[:arbiter, :sync, :outbox, :processor, :run]` with duration, status, limit, and aggregate counts only.
- `rebuild_user_access_projection` execution through `Arbiter.ReadModels.rebuild_user_access_projection/4`, which invalidates old rows and rebuilds active projections from current user and chunk state.
- Gateway stale snapshot checks for user and resource policy versions.
- Gateway read model scope injection for passing accessible chunk ids to retrieval adapters without introducing a direct Repo/read-model dependency in the hot-path core.
