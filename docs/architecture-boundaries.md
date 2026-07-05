# Architecture Boundary Review

[한국어](architecture-boundaries.ko.md)

This note records the current compile-time boundary configuration.

## Current Boundary Spec

Command:

```sh
mix boundary.spec
```

Declared groups:

| Boundary | Exports | Dependencies |
| --- | --- | --- |
| `Arbiter` | domain boundary modules | none |
| `Arbiter.Adapters` | `Cache`, `Search` | `Arbiter.Retrieval` |
| `Arbiter.Adapters.Cache` | `Memory` | none |
| `Arbiter.Adapters.Search` | `Memory` | `Arbiter.Retrieval` |
| `Arbiter.Agents` | `AgentRun` | `Arbiter.Tenants` |
| `Arbiter.Application` | none | `Arbiter`, `ArbiterWeb` |
| `Arbiter.Authorizers` | `Casbin`, `RepoBacked` | `Arbiter.Policy`, `Arbiter.Repo`, `Arbiter.Tenants` |
| `Arbiter.Audit` | `AnswerLineage` | `Arbiter.Policy`, `Arbiter.Repo`, `Arbiter.Retrieval` |
| `Arbiter.Documents` | `Chunk`, `Document` | `Arbiter.Tenants` |
| `Arbiter.Gateway` | `Error`, `Result`, `ToolCall` | `Arbiter.Policy`, `Arbiter.Retrieval` |
| `Arbiter.Policy` | policy core structs, authorizer, and modules | none |
| `Arbiter.ReadModels` | `AccessibleDocumentChunk`, `AccessibleDocumentChunkBuilder` | `Arbiter.Documents`, `Arbiter.Policy`, `Arbiter.Repo`, `Arbiter.Tenants` |
| `Arbiter.Repo` | none | none |
| `Arbiter.Retrieval` | retrieval guard structs and modules | `Arbiter.Policy` |
| `Arbiter.Sync` | outbox, revoke, processor, worker modules | `Arbiter.Adapters`, `Arbiter.Policy`, `Arbiter.ReadModels`, `Arbiter.Repo`, `Arbiter.Tenants` |
| `Arbiter.Tenants` | tenant schemas | none |
| `ArbiterWeb` | Phoenix web modules | none |

## Enforced Rules

- Deep `Arbiter.Policy` and `Arbiter.Retrieval` modules cannot call `Arbiter.Repo`.
- `Arbiter.Gateway` can depend on policy and retrieval contracts, but not Repo, read models, sync, audit, web, cache, vector, or HTTP adapters.
- Adapter contracts and concrete adapter implementations live behind `Arbiter.Adapters`.
- Repo-backed and external authorizer shells live behind `Arbiter.Authorizers`; `Arbiter.Policy` remains pure.
- `Arbiter.ReadModels` owns projection storage and may use Repo, command schemas, and policy decision structs.
- `Arbiter.Sync` owns outbox/revoke orchestration and may call read model and Repo boundaries.
- `Arbiter.Application` is the composition root for the domain app and Phoenix web boundary.

## Review Commands

Boundary checks run during compilation:

```sh
mix compile --warnings-as-errors
```

Use xref when debugging dependency shape:

```sh
mix xref graph --format cycles --label compile-connected
mix xref graph --format stats --label compile-connected
mix xref trace lib/path/to/file.ex --label compile
```

Before adding cache, vector/search, SaaS, or HTTP adapters, define whether they belong under `Arbiter.Sync`, a new adapter boundary, or a narrower boundary documented here.
