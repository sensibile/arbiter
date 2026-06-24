# Arbiter 아키텍처

[English](architecture.md)

이 문서는 현재 구현된 MVP 아키텍처를 요약합니다. 제품과 아키텍처의 원천 문서는 `ARBITER_DIRECTION.md`이며, 이 문서는 현재 코드 계약을 추적합니다.

## MVP 상태

첫 번째 MVP 흐름은 revoke simulation 단계까지 구현되어 있습니다.

1. Domain skeleton
2. 최소 Policy DSL
3. Scope compiler
4. Retrieval guard
5. Gateway
6. Audit lineage
7. Revoke simulation

저장소 전략은 [ADR 0001: Current-State CQRS와 Transactional Outbox](adr/0001-state-sourced-cqrs.ko.md)에 기록되어 있습니다.

## 모듈 경계

### 순수 Policy Core

소유 모듈: `Arbiter.Policy.*`

책임:

- 최소 Policy DSL을 AST로 파싱합니다.
- allow/deny decision을 평가합니다.
- decision reason과 policy scope를 생성합니다.
- scope를 SQL predicate와 vector metadata filter로 compile합니다.
- `Arbiter.Policy.Version`을 통해 MVP policy version을 증가시킵니다.

경계 규칙:

- Policy 모듈은 `Arbiter.Repo`, HTTP client, vector store, clock, ID generator, process messaging, audit persistence를 호출하지 않아야 합니다.

### Retrieval Core

소유 모듈: `Arbiter.Retrieval.*`

책임:

- 검색 실행 전에 Arbiter vector metadata filter를 강제합니다.
- 호출자가 제공한 retrieval filter를 제거합니다.
- 검색된 chunk를 tenant, department, sensitivity, deletion, policy version metadata 기준으로 검증합니다.
- lineage 기록을 위해 accepted/rejected chunk id를 반환합니다.

경계 규칙:

- Retrieval guard 모듈은 vector store를 직접 호출하지 않아야 합니다. boundary 모듈이 사용할 guarded query와 validation result를 반환합니다.

### Gateway Orchestration

소유 모듈: `Arbiter.Gateway`

책임:

- Agent `ToolCall`을 받습니다.
- 명시적인 registry에서 tool contract를 확인합니다.
- 주입된 authorization 함수를 호출합니다.
- tenant scope mismatch, stale user policy snapshot, stale resource policy snapshot, invalid filter, tool failure, retrieval validation failure를 fail-close 처리합니다.
- 현재 tenant, user, policy version에 대해 접근 가능한 chunk id를 얻기 위해 선택적으로 주입된 read model scope 함수를 호출합니다.
- Retrieval tool adapter에는 Arbiter가 guard한 query만 전달합니다.
- Read model chunk allowlist는 `GuardedQuery.allowed_chunk_ids`로 retrieval adapter에 전달하며, 반환된 chunk가 이 allowlist를 무시하면 fail-close 처리합니다.
- Audit boundary가 저장할 audit event data를 반환합니다.

경계 규칙:

- Gateway는 주입된 함수를 orchestration할 수 있지만 Repo, vector store, SaaS tool, HTTP client, cache, clock, ID generator를 직접 호출하지 않아야 합니다.

### Audit Boundary

소유 모듈: `Arbiter.Audit`

책임:

- Policy decision audit row를 저장합니다.
- Retrieval이 발생했거나 scope/filter 구성 이후 실패한 경우 retrieval trace를 저장합니다.
- Answer lineage를 used chunk와 policy decision id에 연결해 저장합니다.

경계 규칙:

- `Arbiter.Audit`은 audit record를 위한 Repo transaction을 소유합니다. Policy decision과 retrieval guard result는 이 boundary에 들어오기 전에 이미 데이터로 구성되어 있어야 합니다.

### Read Model Boundary

소유 모듈: `Arbiter.ReadModels`, `Arbiter.ReadModels.AccessibleDocumentChunk`, `Arbiter.ReadModels.AccessibleDocumentChunkBuilder`

책임:

- 첫 runtime read model table인 `accessible_document_chunks`를 저장합니다.
- `tenant_id`, `user_id`, `chunk_id`, `user_policy_version` 기준으로 user-to-chunk accessibility를 저장합니다.
- 이미 로드된 user/chunk data와 allow policy decision으로부터 `Arbiter.ReadModels.AccessibleDocumentChunkBuilder`가 projection attrs를 생성합니다.
- Retrieval이 command-side join을 다시 실행하지 않고 stale 또는 deleted chunk를 거를 수 있도록 `chunk_policy_version`과 `chunk_deleted_at`을 projection에 복사합니다.
- `tenant_id`, `user_id`, `user_policy_version`, `chunk_deleted_at IS NULL`, `invalidated_at IS NULL`이 모두 일치할 때만 active accessible chunk id를 반환합니다.
- Revoke가 user policy version을 증가시키면 해당 user의 이전 projection row를 invalidation합니다.

경계 규칙:

- `Arbiter.ReadModels`가 projection storage를 위한 Repo query와 update를 소유합니다.
- `Arbiter.ReadModels.AccessibleDocumentChunkBuilder`는 순수 모듈로 유지해야 합니다. Repo, clock, vector store, process worker, external adapter를 호출하지 않아야 합니다.
- Policy, retrieval guard, gateway 모듈은 이 boundary를 직접 호출하기보다 injected function 또는 orchestration layer를 통해 read model 결과를 사용해야 합니다.
- `accessible_document_chunks`는 파생 저장소입니다. Command store가 authoritative source이며 stale, missing, deleted, invalidated projection row가 access grant가 되어서는 안 됩니다.

### Sync/Revoke와 Outbox Consumer Boundary

소유 모듈: `Arbiter.Sync.RevokeSimulation`, `Arbiter.Sync.Outbox`, `Arbiter.Sync.OutboxEvent`, `Arbiter.Sync.OutboxConsumerCommand`, `Arbiter.Sync.OutboxReadModelDispatch`, `Arbiter.Sync.OutboxConsumer`

책임:

- User access revoke를 시뮬레이션합니다.
- 저장된 최신 user policy version을 읽습니다.
- User policy version을 증가시킵니다.
- User access, tool result, retrieval result cache invalidation command를 반환합니다.
- Policy version 증가와 같은 transaction 안에서 invalidation command outbox row를 저장합니다.
- Revoke audit event shape를 반환합니다.
- `Arbiter.Sync.OutboxConsumerCommand`를 통해 outbox row 상태 전이를 순수 데이터로 결정합니다.
- `Arbiter.Sync.OutboxConsumer`를 통해 사용 가능한 `pending` outbox row를 claim하고 `processing`, `processed`, `failed` 상태 변경을 저장합니다.
- Persisted `id`, `attempts`, `locked_at`이 claim한 row와 여전히 일치할 때만 claimed row를 terminal 상태로 표시합니다.
- `invalidate_user_access_cache` event를 `Arbiter.ReadModels.invalidate_user_access/4`로 dispatch해서 revoke 후 오래된 `accessible_document_chunks` row를 invalidation합니다.

경계 규칙:

- 이 boundary는 propagation command를 outbox row로 저장하고 outbox status persistence를 소유합니다. 실제 cache/process adapter와 background worker는 policy와 retrieval core 바깥에 두어야 합니다.
- `Arbiter.Sync.OutboxConsumerCommand`는 Repo, clock, process, cache adapter, vector/search adapter를 호출하지 않아야 합니다. 호출자가 timestamp를 데이터로 전달합니다.
- `Arbiter.Sync.OutboxReadModelDispatch`는 순수 모듈로 유지해야 합니다. Event payload를 검증하고 read model command를 반환하지만 `Arbiter.Repo` 또는 `Arbiter.ReadModels`를 호출하지 않습니다.

### 저장소 전략

Arbiter는 Event Sourcing 대신 current-state CQRS를 사용합니다.

- Command state는 정규화된 PostgreSQL table에 저장합니다.
- Runtime read model과 vector/search metadata는 projection입니다.
- Audit record는 lineage이며 replay 가능한 command state가 아닙니다.
- Outbox row는 propagation command이며 source of truth가 아닙니다.
- Revoke path는 비동기 projection refresh를 기다리지 않기 위해 policy version 증가와 stale-snapshot fail-close 동작을 사용합니다.
- Outbox 처리는 `pending -> processing -> processed | failed`를 사용합니다. 현재 구현은 supervised background worker가 아니라 claim/mark skeleton입니다.
- `accessible_document_chunks`는 retrieval filtering을 위한 첫 구현 read model table입니다. Active lookup은 tenant, user, user policy version, chunk deletion state, revoke invalidation state로 scope됩니다.

## Fail-Closed 불변식

현재 Arbiter는 다음 보안 불변식을 테스트합니다.

- 권한 없는 chunk는 prompt context에 들어가기 전에 제외됩니다.
- 호출자가 제공한 retrieval filter는 Arbiter scope filter로 대체됩니다.
- 호출자가 제공한 read model allowlist는 retrieval adapter 실행 전에 제거됩니다.
- 주입된 read model chunk allowlist가 있으면 retrieval adapter 결과는 그 allowlist 안에 있어야 합니다.
- 검색된 chunk는 decision policy version 기준으로 post-validation됩니다.
- Policy deny decision은 tool을 실행하지 않습니다.
- Tenant scope mismatch는 fail-close됩니다.
- Stale user/resource policy snapshot은 tool 실행 전에 fail-close됩니다.
- Revoke simulation은 cache key를 invalidation하고 오래된 tool-call snapshot을 차단합니다.
- Audit lineage는 allow와 deny decision을 모두 기록합니다.

## 아키텍처 경계 검사

새로운 cross-module dependency를 추가하기 전에 내장 xref 검사를 사용합니다.

```sh
mix xref graph --format cycles --label compile-connected
mix xref graph --format stats --label compile-connected
```

수상한 dependency가 있으면 특정 파일을 trace합니다.

```sh
mix xref trace lib/arbiter/gateway.ex --label compile
```

더 강한 경계 enforcement가 필요하면 `:boundary` 라이브러리를 검토합니다. 이 라이브러리는 module group, 허용 dependency, export module을 정의하고 compilation 중 forbidden call을 보고할 수 있습니다. 첫 적용 후보는 깊은 `Arbiter.Policy`와 `Arbiter.Retrieval` 모듈이 `Arbiter.Repo`를 호출하지 못하게 막는 규칙입니다.

현재 boundary 검토는 [Architecture Boundary Review](architecture-boundaries.ko.md)에 기록되어 있습니다. 현재 `compile-connected` graph 기준으로 `:boundary` 도입은 다음 external adapter 또는 worker slice까지 보류하되, 적용할 규칙 후보는 명시해 둡니다.

## Infrastructure Test

기본 테스트는 로컬 설정 또는 CI service configuration으로 접근 가능한 PostgreSQL 데이터베이스를 전제로 합니다.

새로 시작한 PostgreSQL 컨테이너에서 persistence boundary가 동작하는지 검증할 때는 Testcontainers 기반 infrastructure test를 사용합니다.

```sh
mix infra.test
```

Infrastructure test는 기본 `test/` 트리 밖의 `test_infra/`에 둡니다. 그래서 `mix test`는 빠르게 유지되고 Docker를 요구하지 않습니다.

Coverage는 두 가지 명시적인 모드로 나눕니다.

```sh
mix coverage.core
mix coverage.all
```

순수 policy, retrieval, gateway 로직을 반복 수정할 때는 `mix coverage.core`를 사용합니다. 이 명령은 fast suite를 실행하고 shell, persistence, schema, Phoenix scaffold 모듈을 제외하므로 의도적으로 분리한 boundary가 자주 0% 노이즈로 보이지 않습니다.

큰 변경 완료 시점이나 주기적으로 누락 테스트를 복구할 때는 `mix coverage.all`을 사용합니다. 이 명령은 Testcontainers를 통해 `test/`와 `test_infra/`를 함께 실행하고 전체 모듈을 report에 포함합니다.
