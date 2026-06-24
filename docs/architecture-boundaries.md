# Architecture Boundary Review

[한국어](architecture-boundaries.ko.md)

This note records the current boundary-tool review before adding a compile-time boundary dependency.

## Current Xref Result

Commands run on 2026-06-24:

```sh
mix xref graph --format cycles --label compile-connected
mix xref graph --format stats --label compile-connected
mix xref graph --format plain --label compile-connected
```

Result:

- No compile-time cycles.
- `compile-connected` reported 45 tracked files and 2 compile dependency edges.
- The plain compile-connected graph emitted no dependency lines.

## Decision

Do not add `:boundary` yet.

The current compile graph is still small enough that a new dependency would mostly encode rules that are already documented and manually reviewable. The next good trigger for adding `:boundary` is one of:

- a supervised outbox worker,
- a real vector/search adapter,
- cache adapter integration,
- SaaS connector or HTTP client integration,
- more than one read model boundary module used by gateway/retrieval orchestration.

## Proposed Boundary Rules

When `:boundary` is added, start with these groups:

| Boundary | Modules | May depend on | Must not depend on |
| --- | --- | --- | --- |
| Policy Core | `Arbiter.Policy.*` | Elixir stdlib, policy structs | `Arbiter.Repo`, Ecto query execution, Sync, Audit, ReadModels, Web, external adapters |
| Retrieval Core | `Arbiter.Retrieval.*` | Policy decision structs, scope compiler output | `Arbiter.Repo`, ReadModels, Sync, Audit, Web, vector adapters |
| Gateway Orchestration | `Arbiter.Gateway*` | Policy/Retrieval structs and injected functions | `Arbiter.Repo`, direct HTTP/vector/cache adapters, Web |
| Read Model Boundary | `Arbiter.ReadModels*` | Repo, schema modules, Ecto queries | Policy parser/evaluator internals, Gateway, Web |
| Sync Boundary | `Arbiter.Sync*` | Repo, outbox schemas, pure command modules | Gateway, Web, Retrieval guard internals |
| Audit Boundary | `Arbiter.Audit*` | Repo, audit schemas | Gateway execution, Retrieval guard internals, Web |
| Web Boundary | `ArbiterWeb*` | Public application boundaries | Deep policy/retrieval internals where avoidable |

## Interim Check

Until `:boundary` is installed, use these checks when adding a new cross-boundary call:

```sh
mix xref graph --format cycles --label compile-connected
mix xref graph --format stats --label compile-connected
mix xref trace lib/path/to/file.ex --label compile
```

If a pure core module starts importing `Arbiter.Repo`, `Ecto.Query`, HTTP clients, process workers, cache adapters, or vector adapters, treat that as a boundary violation and move the dependency behind an orchestration or persistence boundary.
