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
- DSL 또는 파싱된 AST를 받는 `Arbiter.Policy.Engine`으로 allow/deny decision을 평가합니다.
- Request subject/action/resource intent가 제공되면 policy `allow` line과 일치하는지 강제합니다.
- RBAC allow/deny와 ABAC retrieval scope 생성을 분리하는 순수 authorizer contract로 Gateway tool call을 authorize합니다.
- RBAC 또는 ABAC decision 전에 `Arbiter.Policy.AuthorizationRequest`로 authorizer input을 정규화합니다.
- decision reason과 policy scope를 생성합니다.
- 공유 audit/decision reason identifier는 `Arbiter.Policy.DecisionReason`에 둡니다.
- scope를 SQL predicate와 vector metadata filter로 compile합니다.
- `Arbiter.Policy.Version`을 통해 MVP policy version을 증가시킵니다.

경계 규칙:

- Policy 모듈은 `Arbiter.Repo`, HTTP client, vector store, clock, ID generator, process messaging, audit persistence를 호출하지 않아야 합니다.
- `Arbiter.Policy.Engine`은 parsing과 evaluation 위의 순수 facade입니다. Policy bundle loading이나 external authorizer 실행을 하지 않습니다.
- 공유 decision reason은 audit row와 lineage record에 저장되므로 안정적인 string identifier로 유지합니다.
- `Arbiter.Policy.AuthorizationRequest`는 authorizer의 안정적인 request contract입니다. Plain map과 Gateway tool call은 request identity validation 전에 정규화됩니다.
- 이 boundary 안의 Authorizer 구현은 이미 로드된 request/user/role data를 받아 `Arbiter.Policy.Decision`을 반환합니다. `Arbiter.Policy.Authorizer.Core`는 공유되는 순수 request identity validation, ABAC scope extraction, decision shaping을 소유합니다.
- Authorizer는 request user id, 로드된 user snapshot id, tenant scope가 일치하지 않으면 fail-close해야 합니다.

### Authorizer Shell Boundary

소유 모듈: `Arbiter.Authorizers.*`

책임:

- `Arbiter.Authorizers.RepoBacked`는 `Arbiter.Repo`에서 현재 저장된 user role과 ABAC attribute를 로드합니다.
- `Arbiter.Authorizers.Casbin`은 주입된 `enforce` 함수를 호출하는 backend-neutral Casbin port를 제공합니다.
- Casbin enforcer를 호출하기 전에 tenant/domain, subject, action, resource type, 선택적 resource id, object identifier를 담은 tuple 형태의 map으로 request를 정규화합니다.
- Repo 접근과 외부 policy engine 호출을 `Arbiter.Policy`와 `Arbiter.Gateway` 밖에 둡니다.
- Repo-backed, Casbin, static authorizer가 같은 request identity와 ABAC fail-close semantics를 공유하도록 `Arbiter.Policy.Authorizer.Core`를 재사용합니다.

경계 규칙:

- Repo-backed authorizer는 `Arbiter.Repo`와 tenant schema를 호출할 수 있지만 authorizer contract를 통해 plain `Arbiter.Policy.Decision`을 반환해야 합니다.
- Casbin authorizer는 enforcer의 non-boolean 응답, raise, throw, timeout을 fail-closed error로 처리해야 합니다.
- Gateway는 여전히 authorizer를 injected function으로 받으며 어떤 authorizer shell이 사용되는지 직접 알지 않아야 합니다.

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
- 주입된 authorizer가 raise 또는 throw하더라도 fail-close 처리합니다.
- 안전한 authorizer error atom은 fail-closed audit reason으로 보존하고, 안전하지 않은 error shape는 `authorization_failed`로 축약합니다.
- 현재 tenant, user, policy version에 대해 접근 가능한 chunk id를 얻기 위해 선택적으로 주입된 read model scope 함수를 호출합니다.
- Retrieval tool adapter에는 Arbiter가 guard한 query만 전달합니다.
- Read model chunk allowlist는 `GuardedQuery.allowed_chunk_ids`로 retrieval adapter에 전달하며, 반환된 chunk가 이 allowlist를 무시하면 fail-close 처리합니다.
- Audit boundary가 저장할 audit event data를 반환합니다.

경계 규칙:

- Gateway는 주입된 함수를 orchestration할 수 있지만 Repo, vector store, SaaS tool, HTTP client, cache, clock, ID generator를 직접 호출하지 않아야 합니다.
- Gateway는 telemetry를 직접 방출하지 않습니다. 관측이 필요한 실행은 `Arbiter.Observability.GatewayTelemetry`를 통합니다.
- Gateway는 authorization 함수를 주입받으며 RBAC role lookup, ABAC attribute loading, policy storage, external authorizer client를 직접 소유하지 않아야 합니다.

### Observability Boundary

소유 모듈: `Arbiter.Observability.*`

책임:

- Runtime telemetry가 필요할 때 Gateway tool call을 감쌉니다.
- Duration과 chunk count measurement를 담은 `[:arbiter, :gateway, :tool_call, :run]` telemetry를 방출합니다.
- Telemetry metadata는 status, decision, primary reason, tool, action, resource type, policy version으로 제한합니다.
- Runtime telemetry가 필요할 때 audit persistence operation을 감쌉니다.
- Duration과 제한된 operation status metadata를 담은 `[:arbiter, :audit, :record, :run]` telemetry를 방출합니다.

경계 규칙:

- Observability 모듈은 telemetry를 방출할 수 있지만 audit record를 저장하거나 Repo, policy store, vector/search adapter, cache, HTTP client, clock, ID generator를 호출하지 않아야 합니다.
- Gateway telemetry에는 tenant, user, agent run, query, prompt, chunk, payload, row identifier를 포함하지 않아야 합니다.
- Audit telemetry에는 tenant, user, agent run, answer, policy decision, query, chunk, payload, row identifier를 포함하지 않아야 합니다.

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

### Adapter Boundary

소유 모듈: `Arbiter.Adapters.*`

책임:

- 외부 또는 교체 가능한 infrastructure를 위한 adapter contract를 정의합니다.
- Cache invalidation behaviour인 `Arbiter.Adapters.Cache`를 제공합니다.
- 테스트와 로컬 개발용 `Arbiter.Adapters.Cache.Memory`를 제공합니다.
- Guarded retrieval search behaviour인 `Arbiter.Adapters.Search`를 제공합니다.
- 테스트와 로컬 개발용 `Arbiter.Adapters.Search.Memory`를 제공합니다.

경계 규칙:

- Adapter contract는 backend-neutral해야 하며 orchestration boundary가 검증한 command를 받아야 합니다.
- Search adapter는 raw caller query map이 아니라 `Arbiter.Retrieval.GuardedQuery`를 받아야 하며, chunk를 반환하기 전에 `allowed_chunk_ids`를 적용해야 합니다.
- Concrete cache, vector/search, SaaS, HTTP client는 이 boundary 또는 문서화된 더 좁은 adapter boundary 뒤에 둡니다.

### Sync/Revoke와 Outbox Consumer Boundary

소유 모듈: `Arbiter.Sync.RevokeSimulation`, `Arbiter.Sync.Outbox`, `Arbiter.Sync.OutboxEvent`, `Arbiter.Sync.OutboxConsumerCommand`, `Arbiter.Sync.OutboxPayload`, `Arbiter.Sync.OutboxReadModelDispatch`, `Arbiter.Sync.OutboxCacheDispatch`, `Arbiter.Sync.OutboxConsumer`, `Arbiter.Sync.OutboxProcessor`, `Arbiter.Sync.OutboxWorker`

책임:

- User access revoke를 시뮬레이션합니다.
- 저장된 최신 user policy version을 읽습니다.
- User policy version을 증가시킵니다.
- User access, tool result, retrieval result cache invalidation command를 반환합니다.
- Policy version 증가와 같은 transaction 안에서 invalidation command outbox row를 저장합니다.
- Revoke audit event shape를 반환합니다.
- `Arbiter.Sync.OutboxConsumerCommand`를 통해 outbox row 상태 전이를 순수 데이터로 결정합니다.
- `Arbiter.Sync.OutboxConsumer`를 통해 사용 가능한 `pending` outbox row를 claim하고 `processing`, `processed`, `failed` 상태 변경을 저장합니다.
- `Arbiter.Sync.OutboxProcessor.run_once/2`를 통해 bounded outbox processing pass를 한 번 실행합니다.
- `Arbiter.Sync.OutboxWorker`를 통해 periodic bounded outbox processing을 선택적으로 schedule합니다. 이 worker는 기본적으로 비활성화되어 있고 process scheduling만 소유합니다.
- 각 processing pass마다 duration과 집계 row count를 담은 `[:arbiter, :sync, :outbox, :processor, :run]` telemetry를 방출합니다.
- Persisted `id`, `attempts`, `locked_at`, 선택적 `locked_by`가 claim한 row와 여전히 일치할 때만 claimed row를 terminal 상태로 표시합니다.
- `invalidate_user_access_cache` event를 `Arbiter.ReadModels.invalidate_user_access/4`로 dispatch해서 revoke 후 오래된 `accessible_document_chunks` row를 invalidation합니다.
- `rebuild_user_access_projection` event를 `Arbiter.ReadModels.rebuild_user_access_projection/4`로 dispatch합니다. 이 함수는 tenant/user/policy version에 해당하는 기존 row를 invalidation한 뒤 현재 user와 chunk 상태에서 active projection을 다시 만듭니다.
- `invalidate_tool_result_cache`와 `invalidate_retrieval_result_cache` event를 검증된 tenant/user/policy-version scope로 configured cache adapter에 dispatch합니다.
- 요청한 user source가 없거나 policy version이 stale이거나 scope가 잘못된 경우 read model rebuild를 fail-closed 처리합니다.

경계 규칙:

- 이 boundary는 propagation command를 outbox row로 저장하고 outbox status persistence를 소유합니다. 실제 cache/process, vector, search adapter는 policy와 retrieval core 바깥에 두어야 합니다.
- `Arbiter.Sync.OutboxConsumerCommand`는 Repo, clock, process, cache adapter, vector/search adapter를 호출하지 않아야 합니다. 호출자가 timestamp를 데이터로 전달합니다.
- `Arbiter.Sync.OutboxPayload`는 dispatch module이 사용하는 순수 outbox payload validation과 identity check를 중앙화합니다.
- `Arbiter.Sync.OutboxReadModelDispatch`는 순수 모듈로 유지해야 합니다. Event payload를 검증하고 read model command를 반환하지만 `Arbiter.Repo` 또는 `Arbiter.ReadModels`를 호출하지 않습니다.
- `Arbiter.Sync.OutboxCacheDispatch`는 순수 모듈로 유지해야 합니다. Event payload를 검증하고 cache adapter command를 반환하지만 adapter를 호출하지 않습니다.
- `Arbiter.Sync.OutboxWorker`는 read model 또는 cache command 세부사항을 알지 않아야 합니다. 설정된 limit, interval, 선택적 worker ownership으로 `Arbiter.Sync.OutboxProcessor.run_once/2`만 schedule합니다.
- Outbox telemetry에는 tenant, user, aggregate, payload, row identifier를 포함하지 않아야 합니다. Pass status, limit, duration, aggregate count만 노출합니다.

### 저장소 전략

Arbiter는 Event Sourcing 대신 current-state CQRS를 사용합니다.

- Command state는 정규화된 PostgreSQL table에 저장합니다.
- Runtime read model과 vector/search metadata는 projection입니다.
- Audit record는 lineage이며 replay 가능한 command state가 아닙니다.
- Outbox row는 propagation command이며 source of truth가 아닙니다.
- Revoke path는 비동기 projection refresh를 기다리지 않기 위해 policy version 증가와 stale-snapshot fail-close 동작을 사용합니다.
- Outbox 처리는 `pending -> processing -> processed | failed`를 사용합니다. 현재 구현은 구현된 read model operation을 위한 bounded `run_once/2` processor와 선택적 supervised worker를 제공합니다.
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

Arbiter는 `:boundary` compiler로 선언된 module group을 compilation 중 enforcement합니다. 현재 group은 다음 명령으로 확인합니다.

```sh
mix boundary.spec
```

새 cross-module dependency를 추가하기 전이나 boundary violation의 dependency shape를 조사할 때는 내장 xref 검사도 사용합니다.

```sh
mix xref graph --format cycles --label compile-connected
mix xref graph --format stats --label compile-connected
```

수상한 dependency가 있으면 특정 파일을 trace합니다.

```sh
mix xref trace lib/arbiter/gateway.ex --label compile
```

현재 boundary 설정은 [Architecture Boundary Review](architecture-boundaries.ko.md)에 기록되어 있습니다. 새 cache, vector/search, SaaS, HTTP adapter는 production wiring 전에 기존 boundary group 뒤에 두거나 새 boundary group으로 문서화해야 합니다.

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
