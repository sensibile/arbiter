# Architecture Boundary Review

[English](architecture-boundaries.md)

이 문서는 compile-time boundary dependency를 추가하기 전에 현재 boundary tool 검토 결과를 기록합니다.

## 현재 Xref 결과

2026-07-05에 실행한 명령:

```sh
mix xref graph --format cycles --label compile-connected
mix xref graph --format stats --label compile-connected
mix xref graph --format plain --label compile-connected
```

결과:

- Compile-time cycle은 없습니다.
- `compile-connected`는 tracked file 51개와 compile dependency edge 2개를 보고했습니다.
- Plain compile-connected graph는 dependency line을 출력하지 않았습니다.

## 결정

아직 `:boundary`를 추가하지 않습니다.

현재 compile graph는 충분히 작아서 새 dependency를 추가해도 이미 문서화되어 있고 수동 검토가 가능한 규칙을 인코딩하는 효과가 더 큽니다. Supervised outbox worker는 여전히 sync boundary에만 의존하므로, `:boundary`를 추가하기 좋은 다음 trigger는 다음 중 하나입니다.

- 실제 vector/search adapter,
- cache adapter integration,
- SaaS connector 또는 HTTP client integration,
- gateway/retrieval orchestration이 사용하는 read model boundary module이 둘 이상으로 늘어나는 시점.

## Boundary 규칙 후보

`:boundary`를 추가할 때는 다음 group으로 시작합니다.

| Boundary | Modules | May depend on | Must not depend on |
| --- | --- | --- | --- |
| Policy Core | `Arbiter.Policy.*` | Elixir stdlib, policy struct | `Arbiter.Repo`, Ecto query execution, Sync, Audit, ReadModels, Web, external adapter |
| Retrieval Core | `Arbiter.Retrieval.*` | Policy decision struct, scope compiler output | `Arbiter.Repo`, ReadModels, Sync, Audit, Web, vector adapter |
| Gateway Orchestration | `Arbiter.Gateway*` | Policy/Retrieval struct와 injected function | `Arbiter.Repo`, direct HTTP/vector/cache adapter, Web |
| Read Model Boundary | `Arbiter.ReadModels*` | Repo, schema module, Ecto query | Policy parser/evaluator internals, Gateway, Web |
| Sync Boundary | `Arbiter.Sync*` | Repo, outbox schema, pure command module | Gateway, Web, Retrieval guard internals |
| Audit Boundary | `Arbiter.Audit*` | Repo, audit schema | Gateway execution, Retrieval guard internals, Web |
| Web Boundary | `ArbiterWeb*` | Public application boundary | 가능한 경우 깊은 policy/retrieval internal |

## 임시 검사

`:boundary`를 설치하기 전에는 새 cross-boundary call을 추가할 때 다음 검사를 사용합니다.

```sh
mix xref graph --format cycles --label compile-connected
mix xref graph --format stats --label compile-connected
mix xref trace lib/path/to/file.ex --label compile
```

순수 core module이 `Arbiter.Repo`, `Ecto.Query`, HTTP client, process worker, cache adapter, vector adapter를 import하거나 호출하기 시작하면 boundary violation으로 보고 orchestration 또는 persistence boundary 뒤로 옮깁니다.
