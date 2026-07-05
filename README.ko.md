# Arbiter

[English](README.md)

Arbiter는 Agentic RAG 시스템을 위한 정책 인식 접근 게이트웨이입니다.

Arbiter는 AI agent가 현재 사용자가 접근할 수 있는 데이터만 검색, 사용, 인용할 수 있도록 보장합니다.

## 해결하는 문제

Agentic RAG 시스템은 tool call을 retrieval infrastructure에 바로 연결하기 쉽습니다. 이 구조에서는 authorization을 일관되게 강제하기 어렵습니다. Filter가 누락될 수 있고, 오래된 policy snapshot이 이전 접근 권한을 계속 허용할 수 있으며, 권한 없는 chunk가 prompt 구성 단계까지 도달한 뒤에야 문제가 드러날 수 있습니다.

Arbiter는 agent tool call과 retrieval infrastructure 사이에 위치합니다. Policy decision을 강제된 search scope로 바꾸고, 검색된 chunk를 prompt 구성 전에 다시 검증하며, allow와 deny 경로 모두에 대해 audit lineage를 기록합니다.

```mermaid
flowchart LR
  Agent["Agent / RAG App"] --> Gateway["Arbiter Gateway"]
  Gateway --> Policy["Policy Decision"]
  Policy --> Scope["Scope Compiler"]
  Scope --> Guard["Guarded Search Query"]
  Guard --> Search["Vector / Search Adapter"]
  Search --> Validate["Post-Retrieval Validation"]
  Validate --> Context["Allowed Context Only"]
  Context --> Answer["LLM Answer"]

  Policy --> Audit["Audit Lineage"]
  Validate --> Audit
  Revoke["Policy Revoke"] --> Outbox["Outbox Invalidation"]
  Outbox --> Refresh["Read Model / Cache Refresh"]
  Refresh --> Gateway
```

## 현재 범위

이 저장소는 `ARBITER_DIRECTION.md`에 설명된 MVP를 Phoenix/Ecto로 구현한 애플리케이션입니다.

현재 구현은 첫 번째 MVP 흐름을 끝까지 한 번 완성한 상태입니다.

- Tenant, user, group, membership
- Document와 chunk
- Policy와 policy decision
- Gateway authorization injection을 위한 static RBAC/ABAC authorizer contract
- Runtime RBAC 확장을 위한 Repo-backed authorizer shell과 Casbin port authorizer shell
- Agent run
- Retrieval trace
- 최소 Policy DSL 파싱과 평가
- Allow-line intent check를 포함한 DSL/AST 평가용 policy engine facade
- SQL predicate와 vector metadata filter로의 scope compilation
- 검색 전 filter 주입과 검색 후 검증을 수행하는 retrieval guard
- 정책 인식 tool call을 위한 gateway orchestration
- Policy decision, retrieval trace, answer lineage 감사 기록
- Policy version 증가, transactional outbox invalidation command, stale snapshot fail-close를 포함한 revoke simulation
- 접근 가능한 chunk read model projection, rebuild 실행, 선택적 supervised outbox processing
- Scoped outbox invalidation을 위한 cache adapter contract와 local in-memory 구현
- Guarded retrieval execution을 위한 search adapter contract와 local in-memory 구현

구현된 모듈 경계와 계약 요약은 `docs/architecture.ko.md`를 참고하세요.
저장소 전략은 `docs/adr/0001-state-sourced-cqrs.ko.md`를 참고하세요.

## 로컬 설정

고정된 로컬 toolchain을 설치합니다.

```sh
mise install
```

로컬 PostgreSQL 의존성을 실행합니다.

```sh
docker compose up -d db
```

의존성 설치, 데이터베이스 생성, migration을 실행합니다.

```sh
mix setup
```

테스트를 실행합니다.

```sh
mix test
```

프로젝트 precommit 검사를 실행합니다.

```sh
mix precommit
```

Testcontainers가 관리하는 PostgreSQL로 infrastructure test를 실행합니다.

```sh
mix infra.test
```

순수 policy, retrieval, gateway 로직을 수정하는 동안에는 core coverage를 사용합니다.

```sh
mix coverage.core
```

큰 변경 완료 시점이나 persistence boundary까지 포함해 누락 테스트를 복구할 때는 full coverage를 사용합니다.

```sh
mix coverage.all
```

`mix coverage.core`는 fast suite를 실행하고 shell, persistence, schema, Phoenix scaffold 모듈을 제외합니다. `mix coverage.all`은 Testcontainers를 통해 `test/`와 `test_infra/`를 함께 실행하고 전체 모듈을 report에 포함합니다.

이 앱은 HTML/assets 없이 API/domain-first로 생성되었습니다. endpoint를 실행하려면 다음 명령을 사용합니다.

```sh
mix phx.server
```

기본 로컬 데이터베이스 URL은 `ecto://postgres:postgres@localhost:55432/arbiter_dev`입니다.
`DATABASE_URL`로 덮어쓸 수 있고, 테스트에서는 `TEST_DATABASE_URL`을 사용할 수 있습니다.

Supervised outbox worker는 기본적으로 비활성화되어 있습니다. App process가 bounded read model propagation pass를 주기적으로 실행해야 할 때 명시적으로 켭니다.

```elixir
config :arbiter, Arbiter.Sync.OutboxWorker,
  enabled: true,
  worker_id: "worker-a",
  interval_ms: 5_000,
  limit: 100
```

`worker_id`는 선택 사항입니다. 값이 있으면 claim된 outbox row의 `locked_by`에 저장되고, terminal update는 이 ownership token까지 일치해야 합니다.

각 outbox processing pass는 duration, status, limit, aggregate row count만 담은 `[:arbiter, :sync, :outbox, :processor, :run]` telemetry를 방출합니다.

## 아키텍처 검사

Boundary enforcement는 `:boundary` compiler를 통해 compilation 중 실행됩니다. 선언된 boundary group을 검토할 때는 다음 명령을 사용합니다.

```sh
mix boundary.spec
```

Compile-time dependency 형태를 조사할 때는 내장 dependency 검사도 계속 유용합니다.

```sh
mix xref graph --format cycles --label compile-connected
mix xref graph --format stats --label compile-connected
```

특정 compile-time dependency를 조사하려면 `mix xref trace path/to/file.ex --label compile`을 사용합니다.

Adapter 작업에서는 새 cache, vector/search, SaaS client를 boundary module 뒤에 둡니다. 금지된 boundary reference가 추가되면 `mix compile --warnings-as-errors`가 실패합니다.
