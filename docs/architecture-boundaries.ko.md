# 아키텍처 Boundary Review

[English](architecture-boundaries.md)

이 문서는 현재 compile-time boundary 설정을 기록합니다.

## 현재 Boundary Spec

명령:

```sh
mix boundary.spec
```

선언된 group:

| Boundary | Export | Dependency |
| --- | --- | --- |
| `Arbiter` | domain boundary module | 없음 |
| `Arbiter.Adapters` | `Cache`, `Search` | `Arbiter.Retrieval` |
| `Arbiter.Adapters.Cache` | `Memory` | 없음 |
| `Arbiter.Adapters.Search` | `Memory` | `Arbiter.Retrieval` |
| `Arbiter.Agents` | `AgentRun` | `Arbiter.Tenants` |
| `Arbiter.Application` | 없음 | `Arbiter`, `ArbiterWeb` |
| `Arbiter.Authorizers` | `Casbin`, `RepoBacked` | `Arbiter.Policy`, `Arbiter.Repo`, `Arbiter.Tenants` |
| `Arbiter.Audit` | `AnswerLineage` | `Arbiter.Policy`, `Arbiter.Repo`, `Arbiter.Retrieval` |
| `Arbiter.Documents` | `Chunk`, `Document` | `Arbiter.Tenants` |
| `Arbiter.Gateway` | `Error`, `Result`, `ToolCall` | `Arbiter.Policy`, `Arbiter.Retrieval` |
| `Arbiter.Policy` | policy core struct, authorizer, module | 없음 |
| `Arbiter.ReadModels` | `AccessibleDocumentChunk`, `AccessibleDocumentChunkBuilder` | `Arbiter.Documents`, `Arbiter.Policy`, `Arbiter.Repo`, `Arbiter.Tenants` |
| `Arbiter.Repo` | 없음 | 없음 |
| `Arbiter.Retrieval` | retrieval guard struct와 module | `Arbiter.Policy` |
| `Arbiter.Sync` | outbox, revoke, processor, worker module | `Arbiter.Adapters`, `Arbiter.Policy`, `Arbiter.ReadModels`, `Arbiter.Repo`, `Arbiter.Tenants` |
| `Arbiter.Tenants` | tenant schema | 없음 |
| `ArbiterWeb` | Phoenix web module | 없음 |

## Enforced Rule

- 깊은 `Arbiter.Policy`와 `Arbiter.Retrieval` module은 `Arbiter.Repo`를 호출할 수 없습니다.
- `Arbiter.Gateway`는 policy와 retrieval contract에 의존할 수 있지만 Repo, read model, sync, audit, web, cache, vector, HTTP adapter에 의존할 수 없습니다.
- Adapter contract와 concrete adapter implementation은 `Arbiter.Adapters` 뒤에 둡니다.
- Repo-backed와 external authorizer shell은 `Arbiter.Authorizers` 뒤에 두며, `Arbiter.Policy`는 순수하게 유지합니다.
- `Arbiter.ReadModels`는 projection storage를 소유하며 Repo, command schema, policy decision struct를 사용할 수 있습니다.
- `Arbiter.Sync`는 outbox/revoke orchestration을 소유하며 read model과 Repo boundary를 호출할 수 있습니다.
- `Arbiter.Application`은 domain app과 Phoenix web boundary의 composition root입니다.

## Review Command

Boundary check는 compilation 중 실행됩니다.

```sh
mix compile --warnings-as-errors
```

Dependency shape를 디버깅할 때는 xref를 사용합니다.

```sh
mix xref graph --format cycles --label compile-connected
mix xref graph --format stats --label compile-connected
mix xref trace lib/path/to/file.ex --label compile
```

Cache, vector/search, SaaS, HTTP adapter를 추가하기 전에는 해당 adapter를 `Arbiter.Sync` 아래에 둘지, 새 adapter boundary로 둘지, 더 좁은 boundary로 둘지 이 문서에 먼저 기록합니다.
