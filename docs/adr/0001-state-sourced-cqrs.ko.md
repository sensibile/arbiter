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
- Production에서는 projection rebuild worker가 필요합니다.
- 중복된 derived state를 versioning rule로 검증해야 합니다.
- Outbox processing에는 idempotency와 retry semantics가 필요합니다.

## 구현 메모

MVP에는 현재 다음 구현이 포함되어 있습니다.

- User policy version 증가를 담당하는 `Arbiter.Sync.RevokeSimulation`
- Persisted propagation command를 위한 `Arbiter.Sync.OutboxEvent`
- Invalidation command changeset을 구성하는 `Arbiter.Sync.Outbox`
- User/resource policy version에 대한 Gateway stale snapshot check
