# Arbiter — Policy-aware Access Control for Agentic RAG

## 1. 프로젝트 개요

**Arbiter**는 Agentic RAG 시스템에서 사용자가 볼 수 없는 데이터를 AI Agent도 검색·사용·인용할 수 없도록 강제하는 **정책 기반 접근 중재 계층**이다.

일반적인 RAG 시스템은 문서 수집, chunking, embedding, vector search, reranking, answer generation에 집중한다. 그러나 B2B/Enterprise 환경에서는 RAG 품질보다 먼저 다음 문제가 해결되어야 한다.

> 사용자가 직접 볼 수 없는 데이터는 Agent도 볼 수 없어야 한다.

Arbiter의 목표는 RAG/Agent 시스템에서 발생하는 데이터 접근 경로 전체에 권한 경계를 심는 것이다.

```text
User
→ Agent
→ Arbiter Gateway
→ Policy Decision
→ Scoped Retrieval / Tool Execution
→ Allowed Context
→ Answer
→ Audit Lineage
```

Arbiter는 단순 RBAC 엔진이 아니다.  
Agentic RAG 환경에서 다음을 함께 다루는 접근 제어 플랫폼이다.

- API-level RBAC
- Retrieval / Query-level ABAC
- Tenant isolation
- Policy DSL
- Predicate / filter compiler
- Agent Tool Gateway
- Vector search guard
- Chunk-level access control
- Audit decision log
- Answer lineage
- Revoke-first authorization model
- Policy versioning
- Cache / projection invalidation

---

## 2. 핵심 문제의식

### 2.1 RAG는 단순 검색 시스템이 아니다

RAG는 원본 데이터를 그대로 조회하는 시스템이 아니라, 데이터를 여러 단계로 복제·가공·재배치한다.

```text
Original document
→ Parsed document
→ Chunk
→ Embedding
→ Vector index
→ Search result
→ Reranked result
→ Prompt context
→ Answer
→ Summary / cache / trace log
```

따라서 원본 문서에만 권한을 걸어서는 부족하다.  
권한은 chunk, vector metadata, cache, agent memory, prompt context, audit trace까지 전파되어야 한다.

### 2.2 Agent는 권한 우회 경로를 만든다

일반 서비스의 접근 경로는 비교적 단순하다.

```text
User → API → DB
```

Agentic RAG에서는 경로가 늘어난다.

```text
User
→ Agent
→ Planner
→ Tool Call
→ Retriever
→ SQL
→ Vector DB
→ SaaS Connector
→ Cache
→ Prompt Builder
```

따라서 API 앞단의 RBAC만으로는 부족하다.  
Agent가 사용하는 모든 tool, retrieval, query는 Arbiter를 통과해야 한다.

### 2.3 중요한 질문

Arbiter는 다음 질문에 답해야 한다.

```text
이 사용자가 이 action을 수행할 수 있는가?
이 사용자가 접근 가능한 데이터 범위는 어디까지인가?
이 query에 어떤 predicate를 주입해야 하는가?
이 vector search에 어떤 metadata filter를 강제해야 하는가?
이 chunk는 prompt context에 들어가도 되는가?
이 answer는 어떤 chunk와 policy decision에 의해 생성되었는가?
권한 회수 후 기존 cache/search result는 무효화되었는가?
```

---

## 3. 핵심 원칙

### 3.1 LLM은 Policy Enforcement Point가 아니다

LLM에게 “권한 없는 데이터는 답하지 마”라고 맡기면 안 된다.

권한 검사는 반드시 다음보다 먼저 수행되어야 한다.

```text
Retrieval 이전
Tool execution 이전
Prompt construction 이전
Answer generation 이전
```

즉, 권한 없는 데이터는 애초에 prompt context에 들어가면 안 된다.

### 3.2 API-level authorization과 Retrieval-level authorization은 다르다

API-level RBAC는 기능 접근을 막는다.

```text
Can user run agent?
Can user create datasource?
Can user view audit log?
```

Retrieval-level ABAC는 데이터 접근 범위를 제한한다.

```text
Can this user retrieve this document chunk?
Which rows can this user query?
Which columns must be masked?
Which vector metadata filter must be applied?
```

Arbiter는 두 계층을 분리해서 다뤄야 한다.

### 3.3 `can()`만으로는 부족하다

전통적인 권한 엔진은 보통 다음 형태다.

```text
can(user, action, resource) -> allow | deny
```

그러나 RAG에서는 더 자주 필요한 것이 다음이다.

```text
scope(user, action, resource_type) -> predicate | filter
```

예를 들어 “이 사용자가 검색 가능한 문서만 vector search 하라”는 요구는 각 chunk마다 `can()`을 호출하는 방식으로는 비효율적이다.

검색 전에 다음과 같은 filter를 생성해야 한다.

```json
{
  "tenant_id": "tenant_a",
  "department": { "$in": ["finance", "legal"] },
  "sensitivity": { "$lte": 3 },
  "status": { "$ne": "deleted" }
}
```

따라서 Arbiter Policy는 boolean decision뿐 아니라 query predicate / vector filter를 생성할 수 있어야 한다.

### 3.4 권한 부여와 권한 회수는 다르게 취급한다

권한 부여 지연은 불편함이다.

```text
새 권한이 아직 반영되지 않음 → 사용자가 잠시 못 봄
```

권한 회수 지연은 보안 사고다.

```text
회수된 권한이 아직 살아 있음 → 유출 가능
```

따라서 Arbiter는 revoke-first 모델을 따른다.

```text
grant: eventual consistency 일부 허용 가능
revoke: strong consistency 또는 즉시 invalidation 우선
```

### 3.5 장애 시 기본값은 fail-close

권한 판정, policy projection, metadata filter, cache validation에 문제가 생기면 기본적으로 접근을 차단해야 한다.

```text
policy missing → deny
policy version mismatch → deny or revalidate
filter compile failed → deny
tenant context missing → deny
audit write failed for sensitive action → deny or quarantine
```

---

## 4. 전체 모듈 구조

초기 프로젝트는 단일 이름 `Arbiter` 아래에 기능별 모듈을 둔다.

```text
Arbiter
├── Arbiter Policy
├── Arbiter Gateway
├── Arbiter Retrieval
├── Arbiter Audit
├── Arbiter Sync
└── Arbiter Console
```

MVP에서는 다음 네 모듈을 우선 구현한다.

```text
Arbiter Core
├── Policy
├── Gateway
├── Retrieval
└── Audit
```

Sync, Console, SSO, SCIM, KMS, 온프레미스 배포는 후속 단계로 둔다.

---

## 5. Arbiter Policy

### 5.1 역할

Arbiter Policy는 정책 정의, 평가, scope 생성, policy version 관리를 담당한다.

주요 책임:

- RBAC 정책 평가
- ABAC 조건 평가
- Policy DSL parsing
- Policy AST 생성
- Allow / deny decision
- SQL predicate 생성
- Vector metadata filter 생성
- Column masking rule 생성
- Decision reason 생성
- Policy version 관리

### 5.2 정책 예시

```text
policy "contract_chunk_read" {
  allow user retrieve chunk
  when user.tenant_id == chunk.tenant_id
   and user.status == "active"
   and chunk.source == "contracts"
   and user.clearance >= chunk.sensitivity
   and chunk.department in user.departments
}
```

### 5.3 Policy Engine이 반환해야 하는 것

단순 boolean만 반환하면 부족하다.

```json
{
  "decision": "allow",
  "reason": [
    "same_tenant",
    "active_user",
    "clearance_ok",
    "department_scope_matched"
  ],
  "policy_version": "policy_v12",
  "scope": {
    "tenant_id": "tenant_a",
    "department": ["finance", "legal"],
    "max_sensitivity": 3
  }
}
```

### 5.4 주의사항

- 정책은 사람이 이해 가능한 형태여야 한다.
- 런타임에서는 빠르게 평가 가능한 read model로 compile되어야 한다.
- policy version을 반드시 남긴다.
- 과거 decision은 당시 policy version과 함께 저장한다.
- “현재 정책으로 replay하면 과거 판단이 재현된다”는 가정은 위험하다.
- policy 변경 시 cache / projection / index metadata invalidation 전략이 필요하다.

---

## 6. Arbiter Gateway

### 6.1 역할

Arbiter Gateway는 Agent와 외부 tool 사이의 유일한 관문이다.

Agent는 DB, vector DB, SaaS connector, internal service에 직접 접근하지 않는다.

```text
Agent
→ Arbiter Gateway
→ Policy Check
→ Scoped Tool Execution
→ Audit Log
→ Result Filtering
→ Agent
```

### 6.2 Gateway가 통제해야 하는 대상

- SQL query tool
- Vector search tool
- Document search tool
- SaaS connector
- File retrieval tool
- Summary generation tool
- Report generation tool
- Export tool
- Admin tool

### 6.3 Tool Call 처리 흐름

```text
1. Agent가 tool call 요청
2. Gateway가 user / tenant / session / policy context 확인
3. Policy Engine에 action 허용 여부 질의
4. Retrieval 또는 query scope 생성
5. Tool 실행 시 scope 강제 주입
6. 결과에 대해 후처리 검증
7. Audit decision log 기록
8. 허용된 결과만 Agent에 반환
```

### 6.4 주의사항

- Agent가 Gateway를 우회할 수 없어야 한다.
- 내부 service credential을 Agent에게 직접 주지 않는다.
- Tool result cache는 tenant_id, user_id, policy_version을 포함해야 한다.
- 민감 tool은 audit write 실패 시 fail-close를 고려한다.
- Tool별로 required permission과 data scope를 명확히 정의해야 한다.

---

## 7. Arbiter Retrieval

### 7.1 역할

Arbiter Retrieval은 RAG 검색 단계에서 권한을 강제한다.

주요 책임:

- SQL predicate injection
- Vector metadata filter injection
- Chunk-level access control
- Row-level security 연계
- Column-level masking
- Post-retrieval validation
- Retrieval result lineage 생성

### 7.2 중요한 원칙

권한 필터는 top-k 이후가 아니라 top-k 이전에 적용되어야 한다.

잘못된 방식:

```text
1. 전체 vector index에서 top-k 검색
2. 검색 결과를 가져온 뒤 권한 필터링
```

올바른 방식:

```text
1. 사용자 policy scope 계산
2. vector search에 metadata filter 강제
3. 허용된 범위 안에서 top-k 검색
4. 결과를 한 번 더 post-validation
```

### 7.3 Vector Search Filter 예시

```json
{
  "tenant_id": "tenant_a",
  "visibility": { "$in": ["public", "department"] },
  "department": { "$in": ["finance"] },
  "sensitivity": { "$lte": 2 },
  "deleted": false
}
```

### 7.4 SQL Predicate 예시

```sql
WHERE tenant_id = :tenant_id
  AND deleted_at IS NULL
  AND sensitivity_level <= :user_clearance
  AND department_id = ANY(:user_departments)
```

### 7.5 Column Masking 예시

```text
if user.role != "hr_manager":
  mask employee.salary
  mask employee.performance_review
```

### 7.6 주의사항

- 원본 문서 권한과 chunk metadata가 drift될 수 있다.
- 문서 권한 변경 시 chunk / embedding / vector metadata도 갱신되어야 한다.
- 권한 회수 시 기존 search cache, summary cache, agent memory를 invalidation해야 한다.
- Post-retrieval validation은 방어층일 뿐, 주 방어층이 되어서는 안 된다.
- 권한 없는 chunk가 prompt에 들어간 뒤 redaction하는 방식은 늦다.

---

## 8. Arbiter Audit

### 8.1 역할

Arbiter Audit은 단순 request log가 아니라 decision lineage를 남긴다.

기록해야 할 것:

- 누가
- 어느 tenant에서
- 어떤 질문을 했고
- 어떤 Agent run이 실행되었고
- 어떤 tool이 호출되었고
- 어떤 policy decision이 내려졌고
- 어떤 chunk / row / document가 검색되었고
- 어떤 chunk가 prompt context에 들어갔고
- 어떤 답변이 생성되었는가

### 8.2 Audit Event 예시

```json
{
  "event_type": "retrieval_decision",
  "tenant_id": "tenant_a",
  "user_id": "user_123",
  "agent_run_id": "run_456",
  "tool": "semantic_search",
  "action": "retrieve",
  "resource_type": "document_chunk",
  "decision": "allow",
  "policy_version": "policy_v12",
  "reason": [
    "same_tenant",
    "active_user",
    "clearance_ok"
  ],
  "retrieved_chunks": [
    "chunk_001",
    "chunk_002"
  ],
  "created_at": "2026-06-20T10:00:00Z"
}
```

### 8.3 Answer Lineage 예시

```json
{
  "answer_id": "answer_789",
  "agent_run_id": "run_456",
  "tenant_id": "tenant_a",
  "user_id": "user_123",
  "used_chunks": [
    {
      "chunk_id": "chunk_001",
      "document_id": "doc_100",
      "policy_version": "policy_v12"
    }
  ],
  "policy_decisions": [
    "decision_abc"
  ]
}
```

### 8.4 주의사항

- API 호출 로그만으로는 부족하다.
- 어떤 chunk가 prompt에 들어갔는지 추적해야 한다.
- allow뿐 아니라 deny도 기록해야 한다.
- policy decision reason을 남겨야 한다.
- 과거 판단을 현재 정책으로 재해석하면 안 된다.
- 당시 policy version, user attributes, resource attributes snapshot을 함께 남기는 것이 좋다.

---

## 9. Arbiter Sync

MVP 이후 단계에서 구현한다.

### 9.1 역할

Arbiter Sync는 권한 변경, 외부 IdP / SaaS 권한 변경, policy projection, cache invalidation을 담당한다.

주요 책임:

- SCIM / IdP group sync
- User status sync
- Group membership sync
- Resource classification sync
- Source system ACL sync
- Policy projection rebuild
- Cache invalidation
- Revoke event fast path
- Policy version mismatch detection

### 9.2 Revoke 처리 원칙

권한 회수는 가장 높은 우선순위로 처리한다.

```text
UserRemovedFromGroup
→ mark user policy stale
→ invalidate user access cache
→ invalidate tool result cache
→ block retrieval until projection refreshed
→ record revoke event
```

### 9.3 주의사항

- 모든 sync를 eventual consistency로 처리하면 위험하다.
- revoke는 grant와 다르게 취급한다.
- 권한 회수 시 vector index metadata 갱신이 늦어질 수 있다.
- metadata 갱신 전까지는 policy version mismatch로 접근 차단할 수 있어야 한다.
- cache key에는 tenant_id, user_id, policy_version을 포함해야 한다.
- 외부 SaaS 권한과 내부 index 사이의 drift를 감지해야 한다.

---

## 10. Arbiter Console

MVP 이후 단계에서 구현한다.

### 10.1 역할

Arbiter Console은 정책 관리와 감사 조회를 위한 UI다.

주요 기능 후보:

- Tenant 관리
- User / Group 관리
- Role assignment
- Policy template 관리
- Policy DSL editor
- Policy simulation
- Audit viewer
- Answer lineage viewer
- Revoke / invalidation 상태 확인
- Data classification 관리

### 10.2 UX 원칙

권한 관리를 단순 체크박스 UX로만 만들면 복잡한 엔터프라이즈 정책을 감당하기 어렵다.

추천 구조:

```text
Admin UX
→ Policy Template
→ Policy DSL / AST
→ Validation
→ Compile
→ Runtime Read Model
```

즉, UX는 DSL을 대체하는 것이 아니라 DSL을 안전하게 생성하고 검증하는 계층이어야 한다.

---

## 11. 데이터 모델 초안

### 11.1 Tenant

```text
Tenant
- id
- name
- isolation_level
- policy_version
- created_at
```

### 11.2 User

```text
User
- id
- tenant_id
- email
- status
- role
- department_ids
- clearance_level
- policy_version
```

### 11.3 Group

```text
Group
- id
- tenant_id
- name
```

### 11.4 Membership

```text
Membership
- user_id
- group_id
- tenant_id
- source
- effective_from
- effective_until
```

### 11.5 Document

```text
Document
- id
- tenant_id
- source
- owner_id
- department_id
- classification
- sensitivity_level
- status
- acl_version
```

### 11.6 Chunk

```text
Chunk
- id
- document_id
- tenant_id
- text
- embedding_id
- department_id
- sensitivity_level
- visibility
- acl_version
- policy_version
```

### 11.7 Policy

```text
Policy
- id
- tenant_id
- name
- source
- dsl
- ast
- version
- status
- created_at
```

### 11.8 Policy Decision

```text
PolicyDecision
- id
- tenant_id
- user_id
- action
- resource_type
- resource_id
- decision
- reason
- policy_version
- user_snapshot
- resource_snapshot
- created_at
```

### 11.9 Agent Run

```text
AgentRun
- id
- tenant_id
- user_id
- question
- status
- started_at
- completed_at
```

### 11.10 Retrieval Trace

```text
RetrievalTrace
- id
- agent_run_id
- tool
- query
- applied_filter
- retrieved_chunk_ids
- accepted_chunk_ids
- rejected_chunk_ids
- policy_version
- created_at
```

---

## 12. MVP 범위

### 12.1 MVP 목표

MVP의 목표는 다음 문장을 증명하는 것이다.

> 사용자가 볼 수 없는 chunk는 Agent도 검색·사용·인용할 수 없다.

### 12.2 MVP 기능

- Tenant A / B 생성
- User 생성
- Role / department / clearance 설정
- Document 업로드
- Chunk 생성
- Chunk metadata 저장
- 간단한 vector search
- Policy DSL 최소 버전
- API-level RBAC
- Retrieval-level ABAC
- Agent Tool Gateway
- Audit decision log
- Answer lineage
- 권한 회수 후 retrieval 차단 테스트

### 12.3 MVP에서 제외

초기에는 다음을 제외한다.

- SSO / OIDC / SAML
- SCIM
- KMS / BYOK / CMK
- 온프레미스 배포
- Air-gapped 환경
- Unity Catalog / Ranger / Atlas 연동
- 복잡한 ReBAC
- 외부 SaaS 권한 미러링
- 대규모 UI Console

---

## 13. 테스트 불변조건

Arbiter의 핵심은 테스트로 증명되어야 한다.

### Invariant 1

A tenant 사용자는 B tenant chunk를 검색할 수 없다.

```text
Given user.tenant_id = tenant_a
When user searches documents
Then no chunk with tenant_id = tenant_b is returned
```

### Invariant 2

권한 없는 chunk는 top-k 후보에도 들어가면 안 된다.

```text
Vector metadata filter must be applied before top-k selection.
```

### Invariant 3

권한 회수 후 기존 cache/search result는 무효화되어야 한다.

```text
Given user had access to document
When access is revoked
Then cached retrieval result must not be reused
```

### Invariant 4

Agent는 Arbiter Gateway를 우회해서 tool을 호출할 수 없다.

```text
All tool calls must pass through Arbiter Gateway.
```

### Invariant 5

모든 answer는 사용된 chunk와 policy decision으로 추적 가능해야 한다.

```text
Answer must have lineage to allowed chunks and policy decisions.
```

### Invariant 6

Policy version mismatch 발생 시 fail-close한다.

```text
If user policy version or resource policy version is stale,
retrieval must be denied or revalidated.
```

### Invariant 7

권한 없는 데이터가 prompt context에 들어간 뒤 redaction되어서는 안 된다.

```text
Unauthorized data must be excluded before prompt construction.
```

### Invariant 8

Audit log에는 allow와 deny가 모두 기록되어야 한다.

---

## 14. Elixir / OTP 선택 이유

Arbiter는 단순 CRUD API 서버가 아니다.

다음과 같은 비동기적이고 장기 실행되는 흐름이 존재한다.

- Agent run
- Tool call
- Retrieval job
- Policy decision
- Audit logging
- Revoke event
- Cache invalidation
- Projection rebuild
- Connector sync
- Tenant-level isolation
- Background worker

따라서 이 문제는 stateless request/response 서버보다 supervised concurrent system에 가깝다.

Elixir / OTP는 다음 이유로 적합하다.

```text
1. Agent run을 독립 process로 모델링할 수 있다.
2. Tool Gateway를 process boundary로 둘 수 있다.
3. Tenant별 supervisor 구조를 만들 수 있다.
4. 권한 변경/revoke 이벤트를 message passing으로 처리할 수 있다.
5. Audit logging, projection rebuild, connector sync를 worker로 분리할 수 있다.
6. 장애가 난 작업을 전체 시스템 장애로 번지지 않게 격리할 수 있다.
7. AI coding agent가 생성한 코드도 process/module boundary 안에서 검증하기 쉽다.
```

선택의 핵심은 취향이 아니라 실행 모델이다.

> Agentic RAG는 많은 actor와 event가 동시에 움직이는 시스템이다.  
> Elixir/OTP는 이 흐름을 supervision tree, process isolation, message passing으로 자연스럽게 표현할 수 있다.

---

## 15. 구현 시 권장 구조

초기에는 umbrella보다 단일 Phoenix app + context 구조를 추천한다.

```text
lib/arbiter/
├── policy/
├── gateway/
├── retrieval/
├── audit/
├── tenants/
├── agents/
├── documents/
└── sync/
```

추후 복잡도가 커지면 umbrella로 분리할 수 있다.

```text
apps/
├── arbiter_policy/
├── arbiter_gateway/
├── arbiter_retrieval/
├── arbiter_audit/
├── arbiter_sync/
└── arbiter_web/
```

---

## 16. Codex 작업 지침

Codex는 한 번에 전체 시스템을 만들려고 하지 말고, 작은 실험 단위로 진행한다.

### Step 1. Domain skeleton

- Tenant
- User
- Document
- Chunk
- Policy
- PolicyDecision
- AgentRun
- RetrievalTrace

### Step 2. Policy DSL 최소 버전

- 단순 조건식
- AST 생성
- allow / deny evaluation
- decision reason 반환

### Step 3. Scope compiler

- Policy scope를 SQL predicate 형태로 변환
- Policy scope를 vector metadata filter 형태로 변환

### Step 4. Retrieval guard

- 검색 전에 filter 강제
- 검색 후 post-validation
- retrieved / accepted / rejected chunk 기록

### Step 5. Gateway

- Agent tool call이 Gateway를 통과하도록 구성
- tool별 permission check
- audit log 기록

### Step 6. Audit lineage

- policy decision 기록
- retrieval trace 기록
- answer와 used chunks 연결

### Step 7. Revoke simulation

- user access revoke
- policy_version 증가
- cache invalidation
- stale policy 접근 차단 테스트

---

## 17. README 첫 문장 후보

```text
Arbiter is a policy-aware access gateway for Agentic RAG systems.

It ensures that AI agents can only retrieve, use, and cite data the current user is allowed to access.
```

한국어 버전:

```text
Arbiter는 Agentic RAG 시스템을 위한 정책 기반 접근 중재 계층입니다.

사용자가 볼 수 없는 데이터는 Agent도 검색·사용·인용할 수 없도록 강제합니다.
```

---

## 18. 핵심 태그라인

```text
Policy-aware access control for Agentic RAG.
```

또는:

```text
Users cannot see it. Agents cannot retrieve it.
```

또는:

```text
RAG is not just retrieval. It is governed data access.
```

---

## 19. 최종 방향성

Arbiter는 일반적인 RAG 챗봇이 아니다.

Arbiter는 다음 문제를 다룬다.

```text
AI Agent가 기업 데이터에 접근할 때,
사용자 권한, 테넌트 경계, 데이터 민감도, 검색 범위, tool 실행, prompt context, audit lineage를 어떻게 하나의 정책 경계 안에 묶을 것인가?
```

MVP는 작게 시작한다.

```text
Policy
Gateway
Retrieval
Audit
```

그러나 설계 방향은 확장 가능해야 한다.

```text
Sync
Console
SSO/SCIM
KMS
On-prem
Data Governance Integration
ReBAC
```

가장 중요한 것은 다음 원칙이다.

> 권한 없는 데이터는 검색되지 않아야 한다.  
> 검색되지 않은 데이터만 prompt에 들어갈 수 있다.  
> prompt에 들어간 모든 데이터는 감사 가능해야 한다.
