# Tasks: Per-User Authentication and Authorization for the MCP Gateway

**Input**: Design documents from `/specs/002-mcp-gateway-auth/`

**Prerequisites**: `plan.md` (required), `spec.md` (required), `research.md`, `data-model.md`,
`contracts/`, `quickstart.md`

**Tests**: Included because `plan.md` Phase E and the Definition of Done require unit,
integration, and container-level validation. Tests are written before the implementation they
cover.

**Organization**: Tasks are grouped by user story so each story is independently testable.
US1 is the MVP; US2 and US3 can proceed in parallel after US1; US4 depends on US1 and US2.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no incomplete dependencies)
- **[Story]**: `[US1]`, `[US2]`, `[US3]`, `[US4]` for user-story phases only
- Every task includes an exact file path or a concrete repository path

## Path Conventions

- IRIS source: `src/br/musketeers/InteropMCP/`
- Tests: `tests/br/musketeers/InteropMCP/`, `python/tests/`
- Configuration: repository root (`config_http.toml`, `opencode.json`, `docker-compose.yml`,
  `iris.script`, `bootstrap-gateway.script`, `.env.example`)
- Tooling: `scripts/`, `python/smoke/`
- Documentation: `docs/interop-mcp/`, `README.md`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Shared configuration and test scaffolding used by every story.

- [ ] T001 Document `WG_USER`, `WG_PASS`, `INTEROPMCP_MODE`, `INTEROPMCP_DEMO_PASSWORD`, and the client-only `INTEROPMCP_BASIC` placeholder in `.env.example` without real secrets.
- [ ] T002 [P] Add `python/tests/__init__.py` and `python/tests/conftest.py` with fixtures for the bridge base URL, a Basic authorization header, and a `%SYS` SQL query helper in `python/tests/conftest.py`.
- [ ] T003 [P] Verify `.dockerignore` excludes `.env*`, `__pycache__/`, `*.pyc`, `.pytest_cache/`, `.coverage`, and `htmlcov/`; append only the missing patterns.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Shared mode and audit primitives. No user story work starts until these exist.

- [ ] T004 Implement `Setup.SetMode(pMode As %String)` and `Setup.GetMode() As %String` around `^InteropMCP.Config("mode")`; `GetMode()` returns `"secured"` or `"demo"` and defaults to `"secured"` when the global is absent in `src/br/musketeers/InteropMCP/Setup.cls`.
- [ ] T005 [P] Implement `MCPService.RecordAccessDecision(pOutcome As %String, pReason As %String = "") As %Status` and `MCPService.UsernameClaim() As %String` in `src/br/musketeers/InteropMCP/MCPService.cls`; write `%SYS.Audit` `EventType="INTEROPMCP"`, `EventSource="InteropMCP"`, `Event="AccessDenied"` or `"AuthenticationDenied"`, `EventData="user=<claim>;endpoint=<path>;outcome=<outcome>[;reason=<reason>]"`, and never include the `Authorization` value or password.

**Checkpoint**: `Setup.GetMode()` and the audit helper are available; US1 can begin.

---

## Phase 3: User Story 1 - Each Agent Client Connects With Its Own Identity (Priority: P1) - MVP

**Goal**: In secured mode, a valid Basic credential is accepted and missing or invalid
credentials are refused before any tool runs.

**Independent Test**: With `Setup.Run("prod")`, one client with a valid credential lists tools
and invokes a read-only tool; clients with no credential and a wrong password receive 401 and
execute no tool; two valid users keep distinct identities.

### Tests for User Story 1

- [ ] T006 [P] [US1] Add `%UnitTest` coverage in `tests/br/musketeers/InteropMCP/TestAuthProvisioning.cls` asserting the secured `/mcp/interopmcp` app has `AutheEnabled=32`, `Resource=""`, `MatchRoles=""`, `LoginPage=""`, `Type=18`, and `DispatchClass=br.musketeers.InteropMCP.MCPService`.
- [ ] T007 [P] [US1] Add HTTP integration tests in `python/tests/test_mcp_auth_401.py` for a missing `Authorization` header and a wrong password against `http://localhost:8080/mcp/interopmcp`; assert 401, no `tools/list` payload, and no invocation row.

### Implementation for User Story 1

- [ ] T008 [US1] Implement secured endpoint provisioning in `Setup.Run` using an `Exists`/`Create` path for the Type 18 app with `AutheEnabled=32`, `Resource=""`, `MatchRoles=""`, `LoginPage=""`, `NameSpace=target`, and `DispatchClass=br.musketeers.InteropMCP.MCPService` in `src/br/musketeers/InteropMCP/Setup.cls`.
- [ ] T009 [US1] Override `MCPService.Login(skipheader As %Boolean = 1) As %Status` to call `..RecordAccessDecision("authentication-denied", "missing or invalid credential")` and then `Quit ##super(skipheader)` in `src/br/musketeers/InteropMCP/MCPService.cls`.
- [ ] T010 [US1] Set `allow_anonymous = false` and remove `endpoints[].username`/`password` from `config_http.toml`; keep the `[[iris]] server` technical credentials.
- [ ] T011 [US1] Add `"headers": { "Authorization": "{env:INTEROPMCP_BASIC}" }` to the remote `InteropMCP` entry in `opencode.json`.
- [ ] T012 [US1] Extend `python/smoke/mcp_client.py` with `--basic` and HTTP endpoint support so the same client can call `tools/list` and `tools/call` with a Basic header.
- [ ] T013 [US1] Run `TestAuthProvisioning.cls` and `python/tests/test_mcp_auth_401.py`; fix failures and record the command/output in `specs/002-mcp-gateway-auth/quickstart.md` under S1/S2.

**Checkpoint**: US1 is independently testable: valid credential accepted; missing/invalid
credential refused with 401 and no tool execution.

---

## Phase 4: User Story 2 - Access Is Limited to Explicitly Entitled Users (Priority: P2)

**Goal**: A valid user without `InteropMCP_Access` is denied at the endpoint with 403 before
the catalog; entitlement revocation takes effect on the next request.

**Independent Test**: With a valid credential but no `InteropMCPRoles`, the caller receives 403
and sees no catalog/result; after granting the role, the caller succeeds; after revoking the
role, the next request is 403 without reconnect.

### Tests for User Story 2

- [ ] T014 [P] [US2] Add `%UnitTest` coverage in `tests/br/musketeers/InteropMCP/TestAccessDecision.cls` for `AccessCheck` returning 403, `Event=AccessDenied`, `Username=$USERNAME`, a populated endpoint/outcome, and no credential in `EventData`.
- [ ] T015 [P] [US2] Add HTTP integration tests in `python/tests/test_mcp_auth_403.py` for a valid user without the entitlement, an entitled user, and a role revoked between two requests; assert 403 before any catalog/result and no reconnect.

### Implementation for User Story 2

- [ ] T016 [US2] Implement `Setup.EnsureSecurity()` in `src/br/musketeers/InteropMCP/Setup.cls`: create `InteropMCP_Access` with `PublicPermission=""` and `Type=9` when absent; create/reconcile `InteropMCPRoles` with `InteropMCP_Access:U,%DB_IRISAPP_CODE:R,%DB_IRISAPP_DATA:RW,%DB_IRISLIB:R,%DB_IRISTEMP:RW,%Service_SQL:U`, preserving unrelated existing grants; require `Security.System.AuditEnabled=1` in secured mode.
- [ ] T017 [US2] Add `Parameter RESOURCE = "InteropMCP_Access";` and override `AccessCheck(Output pAuthorized As %Boolean = 0) As %Status` in `src/br/musketeers/InteropMCP/MCPService.cls`; call `##super(.pAuthorized)`, record `AccessDenied` when `pAuthorized=0`, and return the base status unchanged.
- [ ] T018 [US2] Update `Setup.Run` to call `EnsureSecurity()`, assert `$PARAMETER("br.musketeers.InteropMCP.MCPService","RESOURCE")` is non-empty in secured mode, and fail with an actionable error naming `MCPService`/`RESOURCE` if it is empty in `src/br/musketeers/InteropMCP/Setup.cls`.
- [ ] T019 [US2] Run `TestAccessDecision.cls` and `python/tests/test_mcp_auth_403.py`; fix failures and record the command/output in `specs/002-mcp-gateway-auth/quickstart.md` under S3/S6.

**Checkpoint**: US1 and US2 work together: valid but unentitled users get 403; entitled users
succeed; revocation is immediate on the next request.

---

## Phase 5: User Story 3 - Every Invocation Is Attributed to a Real Person (Priority: P3)

**Goal**: Every invocation records the authenticated `$USERNAME`, demo calls record
`local-dev`, and the status tool exposes the identity.

**Independent Test**: Two users invoke the same tool; the invocation rows and
`GetInvocationStatus` show two distinct identities; a demo call shows `local-dev`, never
`"agent"` or `UnknownUser`.

### Tests for User Story 3

- [ ] T020 [P] [US3] Add `%UnitTest` coverage in `tests/br/musketeers/InteropMCP/TestCurrentAgent.cls` for secured `$USERNAME`, demo mode, empty `$USERNAME`, and `UnknownUser`; assert `local-dev` only for the demo/empty/unknown cases.
- [ ] T021 [P] [US3] Add HTTP integration coverage in `python/tests/test_mcp_identity.py` for two users and at least 20 interleaved calls; assert distinct `AgentIdentity` values and no `"agent"`/`UnknownUser`.

### Implementation for User Story 3

- [ ] T022 [US3] Implement `Guardrails.CurrentAgent() As %String` in `src/br/musketeers/InteropMCP/Guardrails.cls`: return `local-dev` when `Setup.GetMode()="demo"` or `$USERNAME` is empty/`UnknownUser`; otherwise return `$USERNAME`.
- [ ] T023 [US3] Change `Registry.GenerateToolsClass()` to emit `##class(br.musketeers.InteropMCP.Guardrails).CurrentAgent()` for both the `Guardrails.Check` and `Invoker.Invoke` calls in `src/br/musketeers/InteropMCP/Registry.cls`.
- [ ] T024 [US3] Regenerate `src/br/musketeers/InteropMCP/GeneratedTools.cls` by running `BuildCatalog`; do not hand-edit the generated file.
- [ ] T025 [US3] Add `AgentIdentity:%String` to the `GetInvocationStatus` `ROWSPEC` and `SELECT` in `src/br/musketeers/InteropMCP/InvocationStatusTools.cls`.
- [ ] T026 [US3] Update the `AgentIdentity` contract in `src/br/musketeers/InteropMCP/Invocations.cls` (`MAXLEN = 200`, authenticated user or `local-dev`, never `"agent"`) and confirm `src/br/musketeers/InteropMCP/Invoker.cls` passes the caller identity unchanged.
- [ ] T027 [US3] Run `TestCurrentAgent.cls` and `python/tests/test_mcp_identity.py`; fix failures and record the command/output in `specs/002-mcp-gateway-auth/quickstart.md` under S4/S5.

**Checkpoint**: US1, US2, and US3 work together: every call is authorized and attributed to
the correct person.

---

## Phase 6: User Story 4 - Provisioning Is Repeatable and Mode-Aware (Priority: P4)

**Goal**: Setup defaults to secured mode, is idempotent in both modes, switches behavior
correctly, and the startup validator rejects unsafe bridge configurations.

**Independent Test**: Run secured setup three times; one resource/role/app remains and
behavior is unchanged. Run setup without a mode; unauthenticated calls are refused. Switch
secured -> demo -> secured; behavior changes each time. Run the validator with a secured
config containing endpoint credentials; it fails naming the setting.

### Tests for User Story 4

- [ ] T028 [US4] Extend `tests/br/musketeers/InteropMCP/TestAuthProvisioning.cls` with three consecutive secured runs (one resource/role/app, no duplicates), a default-mode run (`Run()` provisions secured), and secured -> demo -> secured transitions.
- [ ] T029 [P] [US4] Add `python/tests/test_config_validator.py` covering secured+`allow_anonymous=true`, demo+`allow_anonymous=false`, secured+endpoint `username`/`password`, invalid mode, and unreadable/invalid TOML; assert exit codes and messages name the offending setting without printing a credential.

### Implementation for User Story 4

- [ ] T030 [US4] Change `Setup.Run(pMode As %String = "prod")` to normalize `prod`/`secured` to `secured` and `dev`/`demo` to `demo`, reject any other value with an error naming all four accepted inputs, use `Security.Applications.Exists()` + `Modify()` or `Create()`, and write `^InteropMCP.Config("mode")` only after successful app provisioning in `src/br/musketeers/InteropMCP/Setup.cls`.
- [ ] T031 [US4] Make `Setup.EnsureSecurity()` idempotent in `src/br/musketeers/InteropMCP/Setup.cls`: leave an existing `InteropMCP_Access` unchanged, merge missing grants into an existing `InteropMCPRoles`, preserve unrelated grants, and do not duplicate either definition.
- [ ] T032 [US4] Make `Setup.TearDown()` idempotent and app-only in `src/br/musketeers/InteropMCP/Setup.cls`; it must not delete `InteropMCP_Access`, `InteropMCPRoles`, or demo users.
- [ ] T033 [US4] Implement `scripts/validate-mcp-config.py` with `--config` and `--mode`; use `tomllib` and exit `1` for secured+anonymous, demo+non-anonymous, secured+endpoint credentials, and endpoint entries without `path`; exit `2` for invalid mode or unreadable/invalid TOML; never print a password or token.
- [ ] T034 [US4] Wire `scripts/validate-mcp-config.py` into the `mcp-launcher` command in `docker-compose.yml` before `bootstrap-gateway.script` and `iris-mcp-server`; pass `INTEROPMCP_MODE` and exit non-zero on validation failure.
- [ ] T035 [US4] Change `docker-compose.yml` ports to `127.0.0.1:1972:1972`, `127.0.0.1:52773:52773`, and `127.0.0.1:8080:8080`; add `INTEROPMCP_MODE` and `INTEROPMCP_DEMO_PASSWORD` to the `iris` and `mcp-launcher` environments.
- [ ] T036 [US4] Change `iris.script` to call `##class(br.musketeers.InteropMCP.Setup).Run("prod")` and keep `Demo.Setup` unchanged.
- [ ] T037 [US4] Update `bootstrap-gateway.script` to call `Setup.Run("prod")`, read `INTEROPMCP_DEMO_PASSWORD` from the environment, fail with an actionable error if it is missing, and create/reconcile `mcp_demo` and `mcp_demo2` with `InteropMCPRoles` without hard-coding a password.
- [ ] T038 [US4] Run `TestAuthProvisioning.cls` and `python/tests/test_config_validator.py`; fix failures and record the command/output in `specs/002-mcp-gateway-auth/quickstart.md` under S7/S8/S9.

**Checkpoint**: Setup is secured by default, repeatable, mode-aware, and refuses unsafe bridge
configuration at startup.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, full acceptance validation, and security review.

- [ ] T039 [P] Update `docs/interop-mcp/authentication.md` to match the implemented design: service-level `RESOURCE`, application `Resource=""`, audit events, mode marker, and the 401/403 contract.
- [ ] T040 [P] Update `docs/interop-mcp/architecture.md`, `README.md`, `docs/interop-mcp/troubleshooting.md`, and `docs/interop-mcp/quickstart.md` with secured/demo setup, `INTEROPMCP_MODE`, `INTEROPMCP_BASIC`, demo users, loopback-only exposure, and the Phase 2 boundary.
- [ ] T040a [P] Document that the client credential must stay in sync across `opencode.json`, `.env.example`, `.env`, and the launch shell (`~/.bashrc`); record in `authentication.md` §13 and `troubleshooting.md` that a rebuild does not update the latter two and that opencode must be restarted from a new shell.
- [ ] T041 [P] Correct `specs/001-interop-mcp/tasks.md` T042 to state `AutheEnabled = 32` (Password), not `1`.
- [ ] T042 Run the full `%UnitTest` suite under `tests/br/musketeers/InteropMCP/` and the Python tests under `python/tests/`; fix failures and record the exact commands/results.
- [ ] T043 Run the `quickstart.md` scenarios S1-S10 against the container, including the credential scan, audit query, three-run idempotency, and mode switch; record evidence and any environment-specific adjustments.
- [ ] T044 Perform the security review: least-privilege role grants, audit coverage for both denial types, no credential in logs/records/errors, no static endpoint credential, loopback-only publication, and no broad roles.
- [ ] T045 Re-run the Constitution Check and `specs/002-mcp-gateway-auth/checklists/requirements.md`; update `plan.md` or `spec.md` status/notes if the implementation changed any decision.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies; T001-T003 can start immediately.
- **Foundational (Phase 2)**: Depends on Setup; T004/T005 block all user stories.
- **US1 (Phase 3)**: Depends on Foundational. This is the MVP.
- **US2 (Phase 4)**: Depends on US1 for end-to-end 403/revocation tests; its resource/role code
  can start after Foundational.
- **US3 (Phase 5)**: Depends on US1 for authenticated identity; can run in parallel with US2.
- **US4 (Phase 6)**: Depends on US1 and US2 because it reconciles the endpoint, resource, and
  role definitions.
- **Polish (Phase 7)**: Depends on all desired user stories.

### User Story Dependencies

- **US1 (P1)**: No user-story dependency; requires Foundational.
- **US2 (P2)**: Requires US1's valid-authentication path; independent test uses a valid user
  without entitlement.
- **US3 (P3)**: Requires US1's authenticated identity; independent test uses two valid users.
- **US4 (P4)**: Requires US1 and US2 definitions; independent test exercises idempotency,
  default mode, and mode switching.

### Within Each User Story

- Write the tests first and confirm they fail for the intended reason.
- Implement provisioning/service code before integration wiring.
- Run the story's tests before moving to the next priority.
- US1 T006/T007 can run in parallel; US2 T014/T015 can run in parallel; US3 T020/T021 can run
  in parallel; US4 T028/T029 can run in parallel.

### Parallel Opportunities

- Setup: T002 and T003.
- Foundational: T004 and T005 (different files).
- US1: T006 and T007; T008-T012 touch different files after the foundation.
- US2: T014 and T015; T016 and T017 touch different files; T018 follows T016.
- US3: T020 and T021; T022, T023, T025, and T026 touch different files; T024 depends on T023.
- US4: T028 and T029; T033, T035, T036, and T037 touch different files; T030-T032 share
  `Setup.cls` and run sequentially; T034 follows T033.
- Polish: T039, T040, and T041.

---

## Parallel Example: User Story 1

```bash
# Tests first (different files)
Task: "Add TestAuthProvisioning.cls coverage in tests/br/musketeers/InteropMCP/TestAuthProvisioning.cls"
Task: "Add 401 HTTP tests in python/tests/test_mcp_auth_401.py"

# Implementation after the foundation (different files)
Task: "Implement secured app provisioning in src/br/musketeers/InteropMCP/Setup.cls"
Task: "Implement MCPService.Login in src/br/musketeers/InteropMCP/MCPService.cls"
Task: "Set allow_anonymous=false in config_http.toml"
Task: "Add the Basic header to opencode.json"
Task: "Extend python/smoke/mcp_client.py with --basic"
```

## Parallel Example: User Story 2

```bash
Task: "Add TestAccessDecision.cls in tests/br/musketeers/InteropMCP/TestAccessDecision.cls"
Task: "Add 403/revocation tests in python/tests/test_mcp_auth_403.py"

Task: "Implement Setup.EnsureSecurity in src/br/musketeers/InteropMCP/Setup.cls"
Task: "Add Parameter RESOURCE and AccessCheck in src/br/musketeers/InteropMCP/MCPService.cls"
```

## Parallel Example: User Story 3

```bash
Task: "Add TestCurrentAgent.cls in tests/br/musketeers/InteropMCP/TestCurrentAgent.cls"
Task: "Add identity isolation tests in python/tests/test_mcp_identity.py"

Task: "Implement Guardrails.CurrentAgent in src/br/musketeers/InteropMCP/Guardrails.cls"
Task: "Update Registry.GenerateToolsClass in src/br/musketeers/InteropMCP/Registry.cls"
Task: "Add AgentIdentity to InvocationStatusTools in src/br/musketeers/InteropMCP/InvocationStatusTools.cls"
```

## Parallel Example: User Story 4

```bash
Task: "Extend TestAuthProvisioning.cls for idempotency/mode switching"
Task: "Add validator tests in python/tests/test_config_validator.py"

Task: "Implement scripts/validate-mcp-config.py"
Task: "Update ports/env in docker-compose.yml"
Task: "Change iris.script to Run(\"prod\")"
Task: "Update bootstrap-gateway.script for secured demo users"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup.
2. Complete Phase 2: Foundational.
3. Complete Phase 3: US1.
4. Stop and validate: valid credential accepted; missing/invalid credential returns 401 and
   executes no tool; two users keep distinct identities.
5. Deploy/demo the secured endpoint if ready.

### Incremental Delivery

1. Setup + Foundational -> shared mode/audit primitives.
2. US1 -> per-user authentication (MVP).
3. US2 -> entitlement and 403/revocation.
4. US3 -> identity attribution and status exposure.
5. US4 -> idempotent, mode-aware provisioning and startup validation.
6. Polish -> docs, full acceptance, security review.

### Parallel Team Strategy

1. Team completes Setup + Foundational together.
2. After Foundational:
   - Developer A: US1 (authentication).
   - Developer B: US2 (entitlement) once US1's valid-auth path is available.
   - Developer C: US3 (identity) once US1's valid-auth path is available.
3. US4 starts after US1 and US2; it reconciles the definitions both stories introduce.
4. Polish after all stories.

---

## Notes

- [P] means different files and no incomplete dependency; same-file tasks run sequentially.
- Tests are included because the plan and Definition of Done require them; verify they fail
  before implementing.
- The service-level `RESOURCE` is the primary entitlement gate; the application `Resource`
  stays empty to preserve the 403 + audit behavior.
- Never log, store, or return the `Authorization` header, Basic token, or password.
- `GeneratedTools.cls` is regenerated by `BuildCatalog`; never hand-edit it.
- Re-run setup in the same mode must not duplicate or downgrade definitions.
- Commit after each task or logical group; stop at each checkpoint to validate the story.
