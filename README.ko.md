# Arbiter

[English](README.md)

Arbiter는 Agentic RAG 시스템을 위한 정책 인식 접근 게이트웨이입니다.

Arbiter는 AI agent가 현재 사용자가 접근할 수 있는 데이터만 검색, 사용, 인용할 수 있도록 보장합니다.

## 현재 범위

이 저장소는 `ARBITER_DIRECTION.md`에 설명된 MVP를 Phoenix/Ecto로 구현한 애플리케이션입니다.

현재 구현은 첫 번째 MVP 흐름을 끝까지 한 번 완성한 상태입니다.

- Tenant, user, group, membership
- Document와 chunk
- Policy와 policy decision
- Agent run
- Retrieval trace
- 최소 Policy DSL 파싱과 평가
- SQL predicate와 vector metadata filter로의 scope compilation
- 검색 전 filter 주입과 검색 후 검증을 수행하는 retrieval guard
- 정책 인식 tool call을 위한 gateway orchestration
- Policy decision, retrieval trace, answer lineage 감사 기록
- Policy version 증가, transactional outbox invalidation command, stale snapshot fail-close를 포함한 revoke simulation

구현된 모듈 경계와 계약 요약은 `docs/architecture.ko.md`를 참고하세요.
저장소 전략은 `docs/adr/0001-state-sourced-cqrs.ko.md`를 참고하세요.

## 로컬 설정

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

이 앱은 HTML/assets 없이 API/domain-first로 생성되었습니다. endpoint를 실행하려면 다음 명령을 사용합니다.

```sh
mix phx.server
```

기본 로컬 데이터베이스 URL은 `ecto://postgres:postgres@localhost:55432/arbiter_dev`입니다.
`DATABASE_URL`로 덮어쓸 수 있고, 테스트에서는 `TEST_DATABASE_URL`을 사용할 수 있습니다.

## 아키텍처 검사

바로 사용할 수 있는 내장 dependency 검사 명령입니다.

```sh
mix xref graph --format cycles --label compile-connected
mix xref graph --format stats --label compile-connected
```

특정 compile-time dependency를 조사하려면 `mix xref trace path/to/file.ex --label compile`을 사용합니다.

더 강한 아키텍처 경계 enforcement가 필요해지면 다음 후보는 `:boundary` 라이브러리입니다. 현재 Arbiter는 명시적인 모듈 계약, 집중된 테스트, xref 검사로 경계를 유지합니다.
