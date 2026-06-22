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
- Projection rebuild workers are still required for production.
- Duplicate derived state must be validated against versioning rules.
- Outbox processing needs idempotency and retry semantics.

## Implementation Notes

The MVP currently includes:

- `Arbiter.Sync.RevokeSimulation` for user policy version bumps.
- `Arbiter.Sync.OutboxEvent` for persisted propagation commands.
- `Arbiter.Sync.Outbox` for shaping invalidation command changesets.
- Gateway stale snapshot checks for user and resource policy versions.
