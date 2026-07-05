# ADR 0001: Current-State CQRS와 Transactional Outbox

[English](0001-state-sourced-cqrs.md)

## 상태

Accepted

## 배경

Arbiter에는 서로 다른 두 가지 트래픽 특성이 있습니다.

- Admin과 sync workflow는 복잡한 policy, tenant, user, group, membership, ACL, classification 변경을 다뤄야 합니다.
- Gateway와 retrieval workflow는 높은 트래픽에서 빠르고 안정적인 읽기를 처리해야 합니다.

Hot path authorization과 retrieval이 매 요청마다 normalized admin table을 join하거나, policy DSL을 parse하거나, user scope를 다시 만들면 안 되므로 CQRS가 필요합니다.

하지만 현재 MVP에는 Event Sourcing이 적합하지 않습니다. Arbiter는 낮은 지연 시간으로 fail-closed authorization을 수행해야 합니다. 보안에 민감한 현재 상태를 event stream에서 재구성하면 hot path에 지연과 운영 위험이 추가됩니다. Audit과 propagation event는 여전히 유용하지만 runtime state의 source of truth가 되어서는 안 됩니다.

## 결정

Arbiter는 **current-state CQRS와 transactional outbox**를 사용합니다.

- PostgreSQL current-state table을 source of truth로 둡니다.
- Runtime read model은 current state에서 파생된 projection입니다.
- Search/vector metadata는 projection이며 source of truth가 아닙니다.
- Audit log는 lineage record이며 command state reconstruction log가 아닙니다.
- Outbox row는 propagation command이며 event-sourced state가 아닙니다.
- Revoke path는 policy version 증가와 invalidation command 기록을 같은 transaction에서 수행합니다.
- Gateway와 retrieval path는 policy version 또는 projection이 stale이면 fail closed됩니다.

## 저장소 모델

### Command Store

정규화된 PostgreSQL table이 현재 상태를 소유합니다.

- tenants
- users
- groups
- memberships
- documents
- chunks
- policies
- audit에 필요한 policy decisions

### Runtime Read Model

향후 projection table은 gateway와 retrieval 읽기에 최적화되어야 합니다.

- user access projections
- policy scope projections
- tool permission projections
- chunk access metadata projections

Projection key에는 `tenant_id`, `user_id`, `policy_version`, resource/action dimension처럼 tenant와 policy-version context가 포함되어야 합니다.

Read model 저장소 계약은 다음과 같습니다.

| Write-side 변경 | Outbox command | Command status | Read model 대상 | 조회 형태 |
| --- | --- | --- | --- | --- |
| User membership, role, status, clearance, policy-version 변경 | `invalidate_user_access_cache` | 구현된 MVP command | User access projection table/cache | `tenant_id`, `user_id`, `policy_version` |
| User membership, role, status, clearance, policy-version 변경 | `rebuild_user_access_projection` | 구현된 MVP command/executor | User access projection table/cache | `tenant_id`, `user_id`, `policy_version` |
| Policy DSL, policy version, scope에 영향을 주는 tenant 설정 변경 | `rebuild_policy_scope_projection` | 계획된 projection command | Policy scope projection table/cache | `tenant_id`, `policy_id`, `resource_type`, `action`, `policy_version` |
| Tool permission 또는 tool contract 변경 | `invalidate_tool_result_cache` | 구현된 MVP command | Tool permission projection/cache | `tenant_id`, `user_id`, `tool`, `action`, `policy_version` |
| Tool permission 또는 tool contract 변경 | `rebuild_tool_permission_projection` | 계획된 projection command | Tool permission projection/cache | `tenant_id`, `user_id`, `tool`, `action`, `policy_version` |
| Document, chunk, ACL, classification, deletion, metadata 변경 | `invalidate_retrieval_result_cache` | 구현된 MVP command | Chunk access metadata table과 vector/search metadata index | `tenant_id`, `chunk_id`, `document_id`, `policy_version`, access metadata |
| Document, chunk, ACL, classification, deletion, metadata 변경 | `refresh_chunk_access_metadata` | 계획된 projection command | Chunk access metadata table과 vector/search metadata index | `tenant_id`, `chunk_id`, `document_id`, `policy_version`, access metadata |

Gateway와 retrieval 코드는 tenant와 policy-version context가 현재 command-store 상태 또는 신뢰 가능한 snapshot과 일치할 때만 projection table, vector metadata, cache entry를 읽을 수 있습니다. Projection이 없거나 stale이거나 실패한 상태이면 보안에 민감한 읽기는 deny/fail-closed 조건입니다.

Projection table과 cache는 파생 저장소입니다. Command-state table에서 다시 만들 수 있어야 하며, command store에 없는 access grant를 새로 만들어서는 안 됩니다.

첫 구현 read model table은 `accessible_document_chunks`입니다. 이 table은 tenant, user, chunk, user policy version을 key로 active user-to-chunk access snapshot을 저장합니다. Retrieval lookup은 tenant, user, user policy version, `chunk_deleted_at IS NULL`, `invalidated_at IS NULL` 조건으로 filter해야 합니다.

첫 Gateway 통합은 의도적으로 작게 유지합니다. `Arbiter.Gateway`는 주입된 read model scope 함수를 받고, 반환된 chunk id를 `GuardedQuery.allowed_chunk_ids`로 retrieval adapter에 전달합니다. Gateway는 `Arbiter.ReadModels` 또는 `Arbiter.Repo`를 직접 호출하지 않습니다. Provider가 사용할 수 없거나, 잘못된 shape를 반환하거나, 빈 scope를 반환하거나, retrieval adapter가 allowlist 밖의 chunk를 반환하면 Gateway는 fail closed됩니다.

### Audit and Lineage

Audit table은 발생한 일을 기록합니다.

- policy decisions
- retrieval traces
- answer lineages
- 향후 추가될 revoke events

이 table들은 설명 가능성과 compliance를 지원합니다. Command state를 replay하기 위한 용도가 아닙니다.

### Transactional Outbox

Outbox table은 propagation work를 기록합니다.

- cache invalidation
- projection rebuild request
- vector/search metadata refresh request

Outbox row는 해당 propagation을 요구하는 current-state 변경과 같은 database transaction 안에서 기록됩니다.

Outbox 처리는 작은 상태 기계를 따릅니다.

```text
pending
→ processing
→ processed | failed
```

Outbox consumer boundary는 사용 가능한 `pending` row를 claim하고, lock timestamp와 증가한 attempt count와 함께 `processing`으로 표시합니다. 이후 projection/cache/index adapter를 실행하고 row를 `processed` 또는 `failed`로 표시합니다. 순수 consumer command는 다음 row 상태를 결정하고, Repo boundary는 row locking, transaction, persistence를 소유합니다.

Terminal marking은 claim ownership을 증명해야 합니다. 현재 구현은 claim한 row의 `id`, `attempts`, `locked_at`, 선택적 `locked_by`를 ownership token으로 사용합니다.

Outbox consumer가 호출하는 projection/cache/index adapter는 idempotent해야 합니다. Outbox는 at-least-once propagation mechanism이므로 동일한 command를 다시 처리해도 read model state가 같은 결과로 수렴해야 합니다.

## Revoke-First 규칙

Grant와 revoke는 다르게 취급합니다.

- Grant는 projection 반영이 조금 늦어도 사용자가 잠시 덜 보게 되는 문제입니다.
- Revoke는 stale access가 데이터 유출로 이어질 수 있으므로 지연을 허용하기 어렵습니다.

Revoke 흐름:

```text
admin revoke command
→ current state update
→ policy version 증가
→ invalidation outbox row 기록
→ commit
→ gateway가 stale policy snapshot 거부
→ worker가 projection과 cache 갱신
```

## 결과

장점:

- Hot path가 복잡한 admin state 대신 안정적인 projection을 읽습니다.
- Current state는 transaction으로 검사하고 변경하기 쉽습니다.
- Revoke 안전성이 asynchronous projection 완료에 의존하지 않습니다.
- Outbox row를 통해 Event Sourcing 없이 propagation을 재시도할 수 있습니다.

Tradeoff:

- Projection freshness를 모니터링해야 합니다.
- 선택적 outbox worker가 구현된 read model operation을 구동할 수 있지만, production에는 여전히 실제 cache/vector/search adapter와 observability가 필요합니다.
- 중복된 derived state를 versioning rule로 검증해야 합니다.
- Outbox processing에는 idempotency와 retry semantics가 필요합니다.

## 구현 메모

MVP에는 현재 다음 구현이 포함되어 있습니다.

- User policy version 증가를 담당하는 `Arbiter.Sync.RevokeSimulation`
- Persisted propagation command를 위한 `Arbiter.Sync.OutboxEvent`
- Invalidation command changeset을 구성하는 `Arbiter.Sync.Outbox`
- 첫 retrieval read model projection table인 `Arbiter.ReadModels.AccessibleDocumentChunk`
- User/chunk/decision을 projection attrs로 순수 변환하는 `Arbiter.ReadModels.AccessibleDocumentChunkBuilder`
- Projection upsert, active lookup, user-policy invalidation을 담당하는 `Arbiter.ReadModels`
- User-access invalidation 및 rebuild outbox event를 read model command로 매핑하는 `Arbiter.Sync.OutboxReadModelDispatch`
- Tool 및 retrieval cache invalidation event를 backend-neutral cache adapter command로 매핑하는 `Arbiter.Sync.OutboxCacheDispatch`
- 교체 가능한 adapter contract를 통해 scoped cache invalidation을 수행하는 `Arbiter.Adapters.Cache`와 `Arbiter.Adapters.Cache.Memory`
- 교체 가능한 adapter contract를 통해 guarded retrieval execution을 수행하는 `Arbiter.Adapters.Search`와 `Arbiter.Adapters.Search.Memory`
- RBAC allow/deny와 ABAC retrieval scope 생성을 포함한 Gateway authorization injection을 위한 `Arbiter.Policy.Authorizer`와 `Arbiter.Policy.Authorizer.Static`
- Pending outbox row를 claim하고 지원되는 read model command를 dispatch한 뒤 row를 processed 또는 failed로 표시하는 bounded pass인 `Arbiter.Sync.OutboxProcessor.run_once/2`
- Bounded outbox processing pass를 선택적으로 supervised scheduling하는 `Arbiter.Sync.OutboxWorker`
- Worker-visible claim provenance와 terminal update 검사를 위한 선택적 `locked_by` outbox ownership
- Duration, status, limit, aggregate count만 포함하는 `[:arbiter, :sync, :outbox, :processor, :run]` outbox processor telemetry
- 기존 row를 invalidation한 뒤 현재 user와 chunk 상태에서 active projection을 다시 만드는 `Arbiter.ReadModels.rebuild_user_access_projection/4` 기반 `rebuild_user_access_projection` 실행
- User/resource policy version에 대한 Gateway stale snapshot check
- Hot-path core에 직접 Repo/read-model dependency를 만들지 않고 accessible chunk id를 retrieval adapter에 전달하는 Gateway read model scope injection
