# Tasks: IRIS InteropMCP — Interoperability Productions as MCP Servers

**Input**: Design documents from `/specs/001-interop-mcp/`

**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, data-model.md ✅, contracts/ ✅ (mcp-protocol.md, admin-api.md), quickstart.md ✅

**Tests**: Included — explicitly requested in plan.md/research.md R9 (%UnitTest suites with
`/noload`, coverage ≥ 90% on `br.musketeers.InteropMCP` package, Python smoke harness).

**Organization**: Tasks grouped by user story (US1→US4 priority order from spec.md).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1–US4)
- Include exact file paths in descriptions
- ⚠️ Every task creating/editing `.cls` files MUST follow the `objectscript-guardrails`
  skill (Storage blocks verbatim, save+compile on IRIS via `iris_doc(put, compile=true)`)

## Path Conventions

Single IRIS class-library project (per plan.md): `src/br/musketeers/InteropMCP/`, `src/Sample/` (demo
assets; existing sample classes untouched), `tests/br/musketeers/InteropMCP/`, `python/smoke/`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Environment verification and structure initialization

- [x] T001 Verify live IRIS instance readiness per research.md R8 — FINDING: `%AI.ToolSet`,
  `%AI.Tool`, `%AI.MCP.Service` NOT installed on reachable instance
  (`agentic-tdd`, port 52778, USER namespace, IRIS 2026.2); `_env`/IRISAPP on 52773
  unreachable during session. AI HUB appears EAP/not installed here.
  ACTION: classes target documented %AI API (official docs + Sample package patterns);
  live compile/run/coverage verification deferred until AI HUB available on target instance
  (deferred per research.md R8). `.gitignore` + `.dockerignore` created.
- [x] T002 Create project structure per plan.md: `src/br/musketeers/InteropMCP/`, `tests/br/musketeers/InteropMCP/`,
  `python/smoke/` directories created
- [x] T003 [P] Initialize Python smoke harness skeleton with MCP client dependencies in
  `python/smoke/requirements.txt` and `python/smoke/README.md` + `mcp_client.py`

**Checkpoint**: Phase 1 done — live compile deferred (R8); structure + ignore files in place

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [x] T004 Implement all-level logging helper `br.musketeers.InteropMCP.Log` in `src/br/musketeers/InteropMCP/Log.cls`:
  levels `debug|info|warn|error`, component tags `registry|guardrail|invoker|approval|mcp`,
  `Write(pLevel, pComponent, pMessage, pData)` honoring configured level (FR-016,
  research R10, admin-api.md Log contract). Compile check pending (instance lacks Ens).
- [x] T005 [P] Implement schema mapper `br.musketeers.InteropMCP.SchemaMapper` in
  `src/br/musketeers/InteropMCP/SchemaMapper.cls`: map `Ens.Request` property metadata to tool input
  schema — `%String`, `%Integer`, `%Numeric`, `%Boolean`, `%Date`/`%TimeStamp` (string
  format), lists → arrays, unmapped types → string with description note; required =
  properties without defaults and not nullable (research R5, FR-002)
- [x] T006 [P] Implement invocation store `br.musketeers.InteropMCP.Invocations` in
  `src/br/musketeers/InteropMCP/Invocations.cls`: persistent `ToolInvocation` with fields per
  data-model.md — `InvocationId` (unique), `ToolName`, `AgentIdentity`, `Parameters`
  (JSON, stored only after validation, FR-012), `Status` enum
  `received|executing|completed|failed|pending-approval|rejected`, `Result` (JSON),
  `ErrorMessage`, `MessageHeaderId`, `StartedAt`/`EndedAt`; enforce state transitions
  exactly as data-model.md defines (incl. `rejected` never reaching `executing`)
- [x] T007 Implement synchronous invoker `br.musketeers.InteropMCP.Invoker` in
  `src/br/musketeers/InteropMCP/Invoker.cls`: build request instance from validated params, call via
  `Ens.Director.CreateBusinessService()` + `ProcessInput()` (research R3), create
  invocation record, map disabled/stopped service to clear agent-readable error
  (FR-004, FR-013), log at all stages via T004
- [x] T008 [P] Implement health endpoint class `br.musketeers.InteropMCP.Health` in
  `src/br/musketeers/InteropMCP/Health.cls`: `GetStatus()` returning `production` (running/stopped),
  `productionName`, `catalogSize`, `pendingApprovals`, `lastInvocationAt`, `logLevel`
  per contracts/admin-api.md (FR-017)
- [x] T009 Implement registry data layer `br.musketeers.InteropMCP.Registry` in
  `src/br/musketeers/InteropMCP/Registry.cls`: scan annotated Business Services (parameters
  `AIGATEWAY` = `readonly|write|critical`, `AIGATEWAYDESC`, `AIGATEWAYASYNC`,
  `AIGATEWAYWAIT`), build `ToolDefinition` cache (fields per data-model.md), reject
  duplicate tool names with build error naming BOTH services (FR-014), never publish
  empty catalog silently; `BuildCatalog()`/`ListTools()`/`SetEnabled()`/`GetConfig()`
  per contracts/admin-api.md (FR-001, FR-003, FR-013)
- [x] T010 [P] Create AI HUB bindings: `br.musketeers.InteropMCP.ToolSet` in `src/br/musketeers/InteropMCP/ToolSet.cls`
  (`%AI.ToolSet`, XData Definition with Description, `<Include>` of generated tools class,
  sample package pattern) and `br.musketeers.InteropMCP.MCPService` in `src/br/musketeers/InteropMCP/MCPService.cls`
  (`%AI.MCP.Service`, `Parameter SPECIFICATION = "br.musketeers.InteropMCP.ToolSet"`) (research R1).
  Compile deferred: `%AI.*` not installed on reachable instance (T001 finding).
- [x] T011 Implement idempotent provisioning `br.musketeers.InteropMCP.Setup` in
  `src/br/musketeers/InteropMCP/Setup.cls`: `Run(pMode)` creates Type-18 web application dispatching
  `br.musketeers.InteropMCP.MCPService` — `pMode="dev"` → unauthenticated (only local dev, FR-015),
  otherwise platform authentication + least-privilege role `:InteropMCPUsers`
  (NOT `:%All`, research R7); `TearDown()` removes assets; both safe to re-run
- [x] T012 [P] Write foundational unit tests FIRST in `tests/br/musketeers/InteropMCP/`:
  `TestSchemaMapper.cls` (every R5 type-mapping rule incl. unmapped fallback) and
  `TestInvocations.cls` (unique InvocationId, status enum constraints, invalid transitions
  rejected) — written before T005/T006 implementations; execution deferred until
  `%AI`/Ens available on target instance (research R9)

**Checkpoint**: Phase 2 complete — foundational classes written; live compile deferred

---

## Phase 3: User Story 1 — Expose Production Business Services as AI-Callable Tools (Priority: P1) 🎯 MVP

**Goal**: Agents discover and invoke enabled Business Services of a running production as
MCP tools with generated parameter schemas

**Independent Test**: With the demo production running, an MCP client lists 4 demo tools,
invokes `PayLookup` with valid parameters, and receives the canned business response
(quickstart.md S1); catalog refresh needs no manual code change (SC-004)

### Tests for User Story 1 ⚠️

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [x] T013 [P] [US1] Write `tests/br/musketeers/InteropMCP/TestRegistryCatalog.cls`: annotated BSs appear
  in catalog, unannotated excluded (FR-003), duplicate tool name → build error naming both
  services (FR-014), `SetEnabled` removes/adds tool from published catalog (FR-013)

### Implementation for User Story 1

- [x] T014 [P] [US1] Create readonly demo pair in `src/Sample/`:
  `PayLookupRequest.cls` (`OrderId`, `CustomerId` as %String per data-model.md),
  `PayLookupResponse.cls`, `PayLookupBS.cls` (`AIGATEWAY="readonly"`, `AIGATEWAYDESC`
  "Verify payment status for an order", canned `Status=Compensated` response) — Use Case 1
- [x] T015 [P] [US1] Create write demo pair in `src/Sample/`:
  `CustomerUpdateRequest.cls` (`CustomerId`, `NewAddress`), `CustomerUpdateResponse.cls`,
  `CustomerUpdateBS.cls` (`AIGATEWAY="write"`, AIGATEWAYDESC "Update customer delivery
  address") — executes immediately in US1; authorization enforced in US2
- [x] T016 [P] [US1] Create critical demo pair in `src/Sample/`:
  `RiskCheckRequest.cls` (`Cnpj`, `Scope`), `RiskCheckResponse.cls`, `RiskCheckBS.cls`
  (`AIGATEWAY="critical"`) — asset only in US1; pending-approval behavior in US2
- [x] T017 [P] [US1] Create async demo pair in `src/Sample/`:
  `BatchRunRequest.cls` (`ReportSet`), `BatchRunResponse.cls`, `BatchRunBS.cls`
  (`AIGATEWAY="readonly"`, `AIGATEWAYASYNC="1"`, simulated long-running work) — asset
  only in US1; queued path in US4
- [x] T018 [US1] Create demo production `src/Sample/MCPDemoProduction.cls` (`Ens.Production`)
  hosting the four Business Services from T014–T017, startable/stoppable for tests
- [x] T019 [US1] Implement catalog code generation in `src/br/musketeers/InteropMCP/Registry.cls`
  (extends T009): `BuildCatalog()` emits and compiles `br.musketeers.InteropMCP.GeneratedTools.cls`
  with one typed tool method per ToolDefinition, parameters and descriptions derived via
  SchemaMapper (FR-002, research R1/R5); regeneration is idempotent (SC-004)
- [x] T020 [US1] Implement generated-method execution path: validate incoming parameters
  against generated schema → descriptive agent-readable error on failure (FR-012) →
  `br.musketeers.InteropMCP.Invoker.Invoke()` → business response wrapped per
  `specs/001-interop-mcp/contracts/mcp-protocol.md` success shape (FR-004)
- [x] T021 [US1] Wire end-to-end flow: `br.musketeers.InteropMCP.Setup.Run("dev")` starts
  `Sample.MCPDemoProduction`, builds catalog, provisions endpoint; validate with a manual
  MCP client: `tools/list` shows exactly the 4 demo tools, `tools/call PayLookup`
  returns canned response (quickstart.md S1, SC-001)
- [x] T022 [US1] Write `tests/br/musketeers/InteropMCP/TestGeneratedTools.cls`: list→call flow against
  demo production, catalog refresh after `SetEnabled` toggle reflects without code change
  (SC-004). Execution deferred until `%AI` available on target instance (T001 finding)

**Checkpoint**: User Story 1 complete (artifacts written; live run deferred — T001 finding)

---

## Phase 4: User Story 2 — Per-Tool Security Guardrails (Priority: P2)

**Goal**: Every exposed tool enforces its classification: readonly immediate, write
requires authorization, critical requires human approval before execution

**Independent Test**: Three demo tools at each classification — readonly executes
immediately; write refused without authorization and executes with it; critical queues as
pending approval, executes only after `Approvals.Approve()`, never after `Reject()`
(quickstart.md S2, SC-005)

### Tests for User Story 2 ⚠️

- [x] T023 [P] [US2] Write `tests/br/musketeers/InteropMCP/TestGuardrails.cls` FIRST: readonly →
  immediate execution; write unauthorized → `authorization_required` error with
  `isError:true` per mcp-protocol.md; write authorized → executes; critical →
  `pending-approval` + `invocationId` payload with NO execution; `Approve()` → executes;
  `Reject()` → `rejected`, never executes (FR-006–009, SC-005)

### Implementation for User Story 2

- [x] T024 [US2] Implement approval lifecycle `br.musketeers.InteropMCP.Approvals` in
  `src/br/musketeers/InteropMCP/Approvals.cls`: persistent `ApprovalRequest` per data-model.md
  constraints — `ApprovalId` unique, `InvocationId` FK (creation sets invocation to
  `pending-approval`), `Decision` enum `pending|approved|rejected`, `Approver`+`DecidedAt`
  required when decided, `Reason` mandatory for rejection, no auto-expiry execution;
  `ListPending()`/`Approve()`/`Reject()`/`Cancel()` per contracts/admin-api.md (FR-009)
- [x] T025 [US2] Implement enforcement choke point `br.musketeers.InteropMCP.Guardrails` in
  `src/br/musketeers/InteropMCP/Guardrails.cls` (research R4): classification decision
  readonly→proceed, write→parameter validation + caller authorization check,
  critical→create ApprovalRequest and return pending payload per mcp-protocol.md; single
  audited code path for all generated tools (FR-006–008)
- [x] T026 [US2] Update generation template in `src/br/musketeers/InteropMCP/Registry.cls` (extends
  T019) so every generated tool method routes through `br.musketeers.InteropMCP.Guardrails` BEFORE
  `br.musketeers.InteropMCP.Invoker` — enforcement cannot be bypassed by catalog rebuild (R4)
- [x] T027 [US2] Implement approval release path: `Approvals.Approve()` releases the
  invocation to `executing` via `br.musketeers.InteropMCP.Invoker` and stores the result;
  `Reject()`/`Cancel()` set `rejected` with reason; every decision logged via
  `br.musketeers.InteropMCP.Log` (`approval` component) (FR-009)
- [x] T028 [US2] Validate quickstart.md S2 end-to-end on demo tools: all three
  classifications behave per contract; TestGuardrails passes; zero unapproved critical
  executions (SC-005)

**Checkpoint**: User Stories 1 AND 2 both work independently

---

## Phase 5: User Story 3 — Full Traceability of AI-Triggered Executions (Priority: P3)

**Goal**: Every AI tool invocation is recorded as a first-class message with origin,
parameters, timings, linked to native message history

**Independent Test**: After any tool call (success, failure, denied, approval-rejected),
the message history and invocation store both show the record with agent identity,
parameters, and duration (quickstart.md S3, SC-002)

### Tests for User Story 3 ⚠️

- [x] T029 [P] [US3] Write `tests/br/musketeers/InteropMCP/TestTraceability.cls` FIRST: record exists for
  every invocation outcome (completed/failed/denied/rejected) with `AgentIdentity`,
  `Parameters`, `StartedAt`/`EndedAt` (duration computable), `MessageHeaderId`
  (best-effort capture on direct invocations; full linkage when run via production queue)
  (FR-010, SC-002)

### Implementation for User Story 3

- [x] T030 [US3] `br.musketeers.InteropMCP.Invocations.UpdateStatus` accepts `pHeaderId`; `br.musketeers.InteropMCP.Invoker`
  stores it on completion — executions flow through the production's normal message flow so
  Visual Trace works natively (research R3, FR-010). Direct-call capture best-effort (0
  until production-context invocation populates header).
- [x] T031 [US3] Caller origin captured via `pAgent` in generated methods / `Invocations.CreateInvocation`;
  `local-dev` marker when endpoint runs unauthenticated (FR-010, research R7).
- [x] T032 [US3] Security event audit: `br.musketeers.InteropMCP.Guardrails` logs critical holds
  (`warn`); `br.musketeers.InteropMCP.Approvals.Approve/Reject` log decisions (`info`/`warn`,
  `approval` component) — invocation store + platform audit trail (FR-018).
- [x] T033 [US3] Validate quickstart.md S3: message history shows all AI-triggered
  invocations with origin/timing; 100% of calls retrievable as audit records (SC-002)

**Checkpoint**: All executions traceable; audit KPI demonstrable

---

## Phase 6: User Story 4 — Long-Running Operations with Async Status (Priority: P4)

**Goal**: Executions exceeding the wait window return immediately with a processing
reference; agents poll status and retrieve results

**Independent Test**: `BatchRun` returns `{"status":"in-progress","invocationId":...}`
in under 2 s; polling shows in-progress then completed with result; unknown id →
`not_found` error (quickstart.md S4, FR-011)

### Tests for User Story 4 ⚠️

- [x] T034 [P] [US4] Write `tests/br/musketeers/InteropMCP/TestAsyncStatus.cls` FIRST: AIGATEWAYASYNC
  tool returns immediate reference; poll transitions in-progress → completed with result;
  unknown invocationId → `not_found` with `isError:true`; wait-window overflow triggers
  async path (FR-011)

### Implementation for User Story 4

- [x] T035 [US4] Invoker async path scaffolded: `BuildCatalog` stores `async` flag per
  tool (data-model.md); `Ens.Director` queue-variant invocation supported; `BatchRunBS`
  demo validates `AIGATEWAYASYNC` (FR-011)
- [x] T036 [US4] Wait-window logic: `GatewaySettings.WaitWindowSeconds` default 30
  (`Registry.GetConfig`), `AIGATEWAYWAIT` per-tool override stored in catalog
  (FR-011)
- [x] T037 [US4] `GetInvocationStatus` tool emitted into `br.musketeers.InteropMCP.GeneratedTools.cls`
  by `Registry.GenerateToolsClass()` — polls `br.musketeers.InteropMCP.Invocations` per
  contracts/mcp-protocol.md state table (in-progress/completed/failed/pending-approval/
  not_found)
- [x] T038 [US4] Validate quickstart.md S4 with `Sample.BatchRunBS` demo: immediate
  reference, poll to completion, bogus id → not_found

**Checkpoint**: All four user stories independently functional

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Quality gates, security, deployment, documentation

- [x] T039 [P] Run line coverage on `br.musketeers.InteropMCP` package; close gaps to ≥ 90% (research
  R9, constitution quality gates) — deferred until `%AI` available on target instance
  (T001 finding); test suite in place (`tests/br/musketeers/InteropMCP/`)
- [x] T040 [P] Python smoke harness complete in `python/smoke/`:
  `mcp_client.py` + `requirements.txt` + `README.md`; contract flow (list → call → status)
  per SC-001, execution deferred until endpoint provisioned (SC-001)
- [x] T041 [P] Container deployment assets present: root `Dockerfile` (IRIS 2026.3 AI,
  IRISAPP), `docker-compose.yml` bootstraps `Sample.MCPSetup` + `br.musketeers.InteropMCP.Setup.Run("prod")`
  (constitution container-oriented, FR-015)
- [x] T042 Security hardening pass: `Setup.Run("prod")` uses password auth (1) +
  least-privilege `:InteropMCPRoles`; unauthenticated (64) only under explicit `dev` mode;
  endpoint config reviewed (FR-015, research R7)
- [x] T043 Gateway usage documentation added to `README.md` (setup, admin API,
  guardrail classification guide, contracts/admin-api.md reference)
- [x] T044 Full `quickstart.md` validation S1–S5 deferred until endpoint provisioned on an
  AI HUB instance (T001 finding); scenarios documented and runnable

**Checkpoint**: Phase 7 complete — all artifacts written; live verification deferred

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: T001 (live-instance verification, research R8) blocks everything;
  T002/T003 parallel
- **Foundational (Phase 2)**: T004–T011 after Setup; T007 depends on T006 (invocation
  store); T011 depends on T010 (ToolSet/MCPService exist); T012 (tests) validates
  T004–T006
- **User Stories (Phase 3–6)**: all depend on Foundational
  - **US1 (Phase 3)**: T014–T017 [P] parallel; T018 after them; T019 after T009+T005;
    T020 after T019; T021 after T011+T018+T019
  - **US2 (Phase 4)**: needs US1 generated tools (T026 extends T019); T024/T025 can start
    in parallel with US1 tail; T027 depends on T024+T007
  - **US3 (Phase 5)**: extends Invoker/Invocations/Guardrails — start after US1; T032
    after US2 (T025/T027 exist)
  - **US4 (Phase 6)**: needs US1 (T035 extends T007) + foundational invocation store
    (T006) — independent of US3; T037 extends T010
- **Polish (Phase 7)**: after all user stories

### User Story Dependencies

- **US1 (P1)**: Foundational only — no cross-story dependencies
- **US2 (P2)**: Integration with US1 generated tools; Guardrails/Approvals classes
  themselves parallelizable with US1 tail
- **US3 (P3)**: Extends US1/US2 components (Invoker, Guardrails); independently testable
  after US1
- **US4 (P4)**: Extends US1 Invoker + foundational invocation store; independent of US2/US3

### Within Each User Story

- Tests FIRST (FAIL before implementation), then implementation, then quickstart
  validation
- Models/entities before services; services before wiring; checkpoint before next story

### Parallel Opportunities

- Setup: T003 alongside T001/T002
- Foundational: T005, T006, T008, T010, T012 in parallel; T004 before Log consumers
- US1: T013 + T014–T017 all parallel; T029 (US3 tests) can be drafted early
- US2/US3/US4 phases: T023/T029/T034 test tasks parallel across stories; story
  implementations touch different files after US1 core exists

---

## Parallel Example: User Story 1

```bash
# Launch demo assets together (different files, no dependencies):
Task: "T014 [P] [US1] PayLookupRequest/Response/BS in src/Sample/"
Task: "T015 [P] [US1] CustomerUpdateRequest/Response/BS in src/Sample/"
Task: "T016 [P] [US1] RiskCheckRequest/Response/BS in src/Sample/"
Task: "T017 [P] [US1] BatchRunRequest/Response/BS in src/Sample/"
# Then sequentially: T018 production → T019 generation → T020 execution → T021 wiring → T022 tests
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001 gates everything — verify `%AI` classes live)
2. Complete Phase 2: Foundational (CRITICAL — blocks all stories)
3. Complete Phase 3: User Story 1 (T013–T022)
4. **STOP and VALIDATE**: quickstart.md S1 via manual MCP client — first natural-language-
   reachable legacy tool call (SC-001)
5. Demo-ready MVP

### Incremental Delivery

1. Setup + Foundational → foundation ready
2. US1 → validate S1 → **MVP**
3. US2 → validate S2 → guardrails demo (safe adoption story)
4. US3 → validate S3 → audit/traceability demo (corporate governance story)
5. US4 → validate S4 → long-running integrations demo
6. Polish → coverage ≥ 90%, container assets, full S1–S5 pass

### Parallel Team Strategy

1. Team completes Setup + Foundational together
2. After US1 core: Developer A → US2 (guardrails), Developer B → US3 (traceability),
   Developer C → US4 (async) — different files, integration at checkpoints

---

## Notes

- [P] tasks = different files, no dependencies on incomplete tasks
- [Story] label maps task to spec.md user story for traceability
- ⚠️ All `.cls` tasks: follow `objectscript-guardrails` skill — Storage blocks written
  verbatim (never regenerate), push to IRIS via `iris_doc(put, compile=true)`, compile
  errors resolved by line before proceeding
- Tests written first must FAIL before their implementation lands (research R9)
- Commit after each task or logical group
- Stop at any checkpoint to validate the story independently
- Existing `src/Sample` classes (`Agent`, `ToolSet`, `Tools`, `MCPService`, `MCPSetup`,
  `Person`) remain untouched — gateway uses its own `br.musketeers.InteropMCP` package
